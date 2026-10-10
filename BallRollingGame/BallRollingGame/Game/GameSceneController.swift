import Combine
import SceneKit
import UIKit

final class GameSceneController: NSObject, ObservableObject {
    @Published private(set) var state: GameState = .menu
    @Published private(set) var distance: Int = 0
    @Published private(set) var selectedSkin: BallSkin = SkinStore.selected
    @Published private(set) var ownedSkins: Set<BallSkin> = Set(BallSkin.allCases.filter { SkinStore.isOwned($0) })
    @Published private(set) var selectedLevel: Biome = .forest
    @Published private(set) var finishPlace: Int = 1
    @Published private(set) var standings: [RaceStanding] = []
    @Published private(set) var raceLengthMeters: Int = 0
    @Published private(set) var totalCoins: Int = CoinStore.total
    @Published private(set) var runCoins: Int = 0
    @Published private(set) var equippedPowerUp: PowerUpType? = PowerUpStore.equipped
    @Published private(set) var powerUpLevels: [PowerUpType: Int] = [:]
    /// HUD: seconds left on cooldown (0 = ready). −1 when nothing equipped.
    @Published private(set) var powerUpCooldownRemaining: Float = -1
    @Published private(set) var powerUpEffectActive: Bool = false
    @Published private(set) var powerUpReady: Bool = false

    let scnView: SCNView
    private let scene = SCNScene()
    private let camera = CameraController()
    private let input = DragInputHandler()
    private var track: TrackGenerator!
    private var trackRoot: SCNNode!
    private var startZ: Float = 0
    private var finishZ: Float = 3080
    private var runTime: Float = 0
    private var lastUpdateTime: TimeInterval = 0
    private var displayedDistance = 0
    private var nextFinishOrder = 1
    private var finishOrders: [ObjectIdentifier: Int] = [:]
    private var raceMarkersRoot: SCNNode?
    private var startLineNode: SCNNode?
    private var finishLineNode: SCNNode?
    /// After the player crosses, lock the chase cam on the finish and let others stream in.
    private var cameraLockedAtFinish = false
    private var awaitingPodium = false
    private var podiumTimer: Float = 0
    private let podiumTimeout: Float = 14
    private var finishLeadMeters: Float = 0
    /// Snap the chase cam for a few frames after kickoff so it doesn't lerp from the finish cam.
    private var startupCameraFrames: Int = 0

    private let baseSpeed: Float = 14
    private let maxSpeed: Float = 40
    private let speedRampPerSecond: Float = 0.65
    /// Nominal race length ≈ 1 minute 30 seconds at the shared speed curve.
    private let raceDurationSeconds: Float = 90

    private var player: BallController!
    private var bots: [BallController] = []
    private var botBrains: [BotBrain] = []
    private var botSpeedScales: [Float] = []
    private var botCatchUpStrength: Float = 0.12
    private var racers: [BallController] { [player] + bots }

    private let playerPowerUp = PowerUpRuntime()
    private var botPowerUps: [PowerUpRuntime] = []
    private var botPowerUpThinkTimers: [Float] = []
    /// HUD taps set this; activation runs on the SceneKit update thread (scene-graph safe).
    private var pendingPlayerPowerUpActivation = false

    private let botColors: [UIColor] = [
        UIColor(red: 0.20, green: 0.55, blue: 0.95, alpha: 1),
        UIColor(red: 0.20, green: 0.78, blue: 0.40, alpha: 1),
        UIColor(red: 0.72, green: 0.35, blue: 0.95, alpha: 1),
        UIColor(red: 0.98, green: 0.78, blue: 0.18, alpha: 1)
    ]
    private let botNames = ["Aqua", "Leaf", "Violet", "Sunny"]
    /// Distinct corridors so bots do not stack on the same line.
    private let botPreferredXs: [Float] = [-14, -6, 6, 14]
    private let botWeaveAmps: [Float] = [2.2, 1.6, 1.9, 2.0]
    private let botWeaveFreqs: [Float] = [0.024, 0.034, 0.028, 0.038]
    private let botWeavePhases: [Float] = [0.0, 1.7, 3.4, 5.1]

    override init() {
        scnView = SCNView(frame: .zero)
        super.init()
        raceLengthMeters = Int(Self.distanceForDuration(
            raceDurationSeconds,
            base: baseSpeed,
            ramp: speedRampPerSecond,
            cap: maxSpeed
        ))
        configureView()
        buildWorld()
        GameArt.warmCaches()
        refreshPowerUpShopState()
        resetToMenu()
    }

    func startPlay() {
        guard state == .menu || state == .biomeRoulette || state == .dead || state == .won else { return }

        // Stop post-race coast immediately so we don't keep growing the track.
        cameraLockedAtFinish = false
        awaitingPodium = false
        podiumTimer = 0
        // Use SceneKit's next render timestamp (not CACurrentMediaTime) for a clean first dt.
        lastUpdateTime = 0
        startupCameraFrames = 3

        track.reset(biome: selectedLevel)
        input.reset()
        runTime = 0
        finishPlace = 1
        nextFinishOrder = 1
        finishOrders.removeAll()
        finishLeadMeters = 0
        runCoins = 0
        totalCoins = CoinStore.total
        pendingPlayerPowerUpActivation = false
        spawnRacersForRun()
        startZ = player.position.z
        let length = Self.distanceForDuration(
            raceDurationSeconds,
            base: baseSpeed,
            ramp: speedRampPerSecond,
            cap: maxSpeed
        )
        finishZ = startZ + length
        raceLengthMeters = Int(length)
        placeRaceMarkers()
        refreshStandings()
        camera.snap(to: player.position)
        state = .playing
        distance = 0
        displayedDistance = 0
    }

    func returnToMenu() {
        guard state == .dead || state == .won || state == .skinShop || state == .powerUpShop || state == .settings || state == .biomeRoulette || state == .paused else { return }
        resetToMenu()
    }

    func pauseRun() {
        guard state == .playing else { return }
        input.reset()
        pendingPlayerPowerUpActivation = false
        // Don't set scene.isPaused — that can deadlock SceneKit's render thread
        // when called from SwiftUI. Skipping updates via `.paused` is enough.
        state = .paused
    }

    func resumeRun() {
        guard state == .paused else { return }
        // Avoid a huge first frame after the pause so nothing teleports forward.
        lastUpdateTime = 0
        state = .playing
    }

    func exitRun() {
        guard state == .paused else { return }
        returnToMenu()
    }

    func openBiomeRoulette() {
        guard state == .menu else { return }
        state = .biomeRoulette
    }

    func openSkinShop() {
        guard state == .menu else { return }
        refreshSkinShopState()
        state = .skinShop
    }

    func openPowerUpShop() {
        guard state == .menu else { return }
        refreshPowerUpShopState()
        state = .powerUpShop
    }

    func openSettings() {
        guard state == .menu else { return }
        state = .settings
    }

    func purchasePowerUp(_ type: PowerUpType) {
        guard state == .powerUpShop else { return }
        guard PowerUpStore.purchase(type) else { return }
        refreshPowerUpShopState()
    }

    func upgradePowerUp(_ type: PowerUpType) {
        guard state == .powerUpShop else { return }
        guard PowerUpStore.upgrade(type) else { return }
        refreshPowerUpShopState()
    }

    func equipPowerUp(_ type: PowerUpType) {
        guard state == .powerUpShop else { return }
        PowerUpStore.equip(type)
        refreshPowerUpShopState()
    }

    func activateEquippedPowerUp() {
        guard state == .playing, !awaitingPodium else { return }
        guard playerPowerUp.isReady else { return }
        // Defer SceneKit node work to `updatePlaying` so we never mutate the
        // scene from the SwiftUI/main thread while the renderer is running.
        pendingPlayerPowerUpActivation = true
    }

    private func processPendingPlayerPowerUpActivation() {
        guard pendingPlayerPowerUpActivation else { return }
        pendingPlayerPowerUpActivation = false
        guard state == .playing, !awaitingPodium else { return }
        guard let activation = playerPowerUp.tryActivate() else { return }
        applyActivationSideEffects(activation, caster: player)
        playActivationVFX(activation, on: player)
        publishPlayerPowerUpHUD()
    }

    private func refreshPowerUpShopState() {
        totalCoins = CoinStore.total
        equippedPowerUp = PowerUpStore.equipped
        var levels: [PowerUpType: Int] = [:]
        for type in PowerUpType.allCases {
            levels[type] = PowerUpStore.level(of: type)
        }
        powerUpLevels = levels
    }

    private func publishPlayerPowerUpHUD() {
        let nextCD: Float
        let nextActive: Bool
        let nextReady: Bool
        if playerPowerUp.hasPowerUp {
            nextCD = playerPowerUp.cooldownRemaining
            nextActive = playerPowerUp.isEffectActive
            nextReady = playerPowerUp.isReady
        } else {
            nextCD = -1
            nextActive = false
            nextReady = false
        }

        // Avoid spamming SwiftUI with sub-frame float noise.
        guard abs(powerUpCooldownRemaining - nextCD) > 0.05
            || powerUpEffectActive != nextActive
            || powerUpReady != nextReady else { return }

        let apply = { [weak self] in
            guard let self else { return }
            self.powerUpCooldownRemaining = nextCD
            self.powerUpEffectActive = nextActive
            self.powerUpReady = nextReady
        }
        // @Published must be updated on the main thread (renderer runs off-main).
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func applyActivationSideEffects(
        _ activation: PowerUpActivation,
        caster: BallController
    ) {
        guard activation.type == .slowPulse else { return }
        let radius = activation.stats.slowRadius
        let multiplier = activation.stats.slowMultiplier
        let duration = activation.stats.duration
        let radiusSq = radius * radius
        let cx = caster.position.x
        let cz = caster.position.z

        for other in racers where other !== caster && other.isAlive {
            let dx = other.position.x - cx
            let dz = other.position.z - cz
            guard dx * dx + dz * dz <= radiusSq else { continue }
            runtime(for: other)?.applyIncomingSlow(multiplier: multiplier, duration: duration)
            // Flash the victim so mid-air / off-camera pulses are still readable.
            other.playSlowPulseHitFlash()
        }
    }

    private func playActivationVFX(_ activation: PowerUpActivation, on caster: BallController) {
        caster.playPowerUpActivation(
            activation.type,
            pulseRadius: activation.stats.slowRadius
        )
    }

    /// Remember the biome; the track loads when play starts.
    func selectLevel(_ biome: Biome) {
        selectedLevel = biome
    }

    /// Pick a biome and jump straight into that race.
    func playLevel(_ biome: Biome) {
        guard state == .biomeRoulette || state == .menu || state == .dead || state == .won else { return }
        selectedLevel = biome
        startPlay()
    }

    func selectSkin(_ skin: BallSkin) {
        guard SkinStore.isOwned(skin) else { return }
        selectedSkin = skin
        SkinStore.selected = skin
        player.applySkin(skin)
        refreshSkinShopState()
    }

    func purchaseSkin(_ skin: BallSkin) {
        guard state == .skinShop else { return }
        guard SkinStore.purchase(skin) else { return }
        selectedSkin = skin
        SkinStore.selected = skin
        player.applySkin(skin)
        refreshSkinShopState()
    }

    private func refreshSkinShopState() {
        ownedSkins = Set(BallSkin.allCases.filter { SkinStore.isOwned($0) })
        selectedSkin = SkinStore.selected
        totalCoins = CoinStore.total
    }

    func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard state == .playing else { return }
        let translation = gesture.translation(in: scnView)
        input.handlePan(translation: translation, state: gesture.state, viewSize: scnView.bounds.size)
    }

    private static func distanceForDuration(
        _ seconds: Float,
        base: Float,
        ramp: Float,
        cap: Float
    ) -> Float {
        let tCap = (cap - base) / ramp
        if seconds <= tCap {
            return base * seconds + 0.5 * ramp * seconds * seconds
        }
        let beforeCap = base * tCap + 0.5 * ramp * tCap * tCap
        return beforeCap + cap * (seconds - tCap)
    }

    private func configureView() {
        scnView.scene = scene
        scnView.backgroundColor = UIColor(red: 0.55, green: 0.78, blue: 0.95, alpha: 1)
        // 2x AA is much cheaper than 4x on dense forest/tropical chunks.
        scnView.antialiasingMode = .multisampling2X
        scnView.isPlaying = true
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = false
        scnView.preferredFramesPerSecond = 60
        scnView.rendersContinuously = true
        scnView.delegate = self

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panRecognized(_:)))
        pan.maximumNumberOfTouches = 1
        scnView.addGestureRecognizer(pan)
    }

    @objc private func panRecognized(_ gesture: UIPanGestureRecognizer) {
        handlePan(gesture)
    }

    private func buildWorld() {
        scene.background.contents = GameArt.skyGradient()
        scene.fogStartDistance = 55
        scene.fogEndDistance = 145
        scene.fogColor = UIColor(red: 0.70, green: 0.84, blue: 0.95, alpha: 1)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 520
        ambient.light?.color = UIColor(red: 0.78, green: 0.85, blue: 0.95, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 780
        sun.light?.color = UIColor(red: 1.0, green: 0.97, blue: 0.90, alpha: 1)
        sun.light?.castsShadow = false
        sun.eulerAngles = SCNVector3(-1.05, 0.45, 0)
        scene.rootNode.addChildNode(sun)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 280
        fill.light?.color = UIColor(red: 0.65, green: 0.75, blue: 0.95, alpha: 1)
        fill.eulerAngles = SCNVector3(-0.4, -0.9, 0)
        scene.rootNode.addChildNode(fill)

        trackRoot = SCNNode()
        trackRoot.name = "trackRoot"
        scene.rootNode.addChildNode(trackRoot)
        track = TrackGenerator(rootNode: trackRoot)

        player = BallController(
            name: "You",
            isPlayer: true,
            material: GameArt.ballMaterial(for: selectedSkin)
        )
        scene.rootNode.addChildNode(player.node)
        player.attachPowerUpVFX(worldRoot: scene.rootNode)

        for i in 0..<4 {
            let bot = BallController(
                name: botNames[i],
                isPlayer: false,
                material: GameArt.botMaterial(color: botColors[i])
            )
            bot.hide()
            bots.append(bot)
            botPowerUps.append(PowerUpRuntime())
            botPowerUpThinkTimers.append(0)
            scene.rootNode.addChildNode(bot.node)
            bot.attachPowerUpVFX(worldRoot: scene.rootNode)
        }
        configureBotsForCurrentDifficulty()

        scene.rootNode.addChildNode(camera.node)
        scnView.pointOfView = camera.node
    }

    /// Rebuild bot brains / speeds from adaptive difficulty (previous race results).
    private func configureBotsForCurrentDifficulty() {
        botBrains = []
        botSpeedScales = []
        var catchUp: Float = 0
        for i in 0..<bots.count {
            let profile = BotDifficultyStore.profile(botIndex: i)
            botBrains.append(
                BotBrain(
                    skill: profile.skill,
                    weaveAmplitude: botWeaveAmps[i],
                    weaveFrequency: botWeaveFreqs[i],
                    weavePhase: botWeavePhases[i],
                    corridorPull: 0.09 + (1 - BotDifficultyStore.rating) * 0.06
                )
            )
            botSpeedScales.append(profile.speedMultiplier)
            catchUp += profile.catchUpStrength
        }
        botCatchUpStrength = bots.isEmpty ? 0.12 : catchUp / Float(bots.count)
    }

    private func hideBots() {
        bots.forEach { $0.hide() }
    }

    private func spawnRacersForRun() {
        configureBotsForCurrentDifficulty()

        // Lined up on the start line.
        let startXs: [Float] = [-9, -4.5, 0, 4.5, 9]
        let lineZ: Float = 0
        player.applySkin(selectedSkin)
        player.beginPlaying(atX: startXs[2], startZ: lineZ)

        if let equipped = PowerUpStore.equipped, PowerUpStore.isOwned(equipped) {
            playerPowerUp.configure(type: equipped, level: PowerUpStore.level(of: equipped))
        } else {
            playerPowerUp.configure(type: nil, level: 0)
        }
        publishPlayerPowerUpHUD()

        for i in 0..<bots.count {
            let x = startXs[i < 2 ? i : i + 1]
            bots[i].applyMaterial(GameArt.botMaterial(color: botColors[i]))
            bots[i].beginPlaying(atX: x, startZ: lineZ)
            botBrains[i].reset(startX: x, preferredX: botPreferredXs[i])

            let botType = PowerUpType.botAssignable.randomElement() ?? .speedBoost
            let skill = botBrains[i].skill
            let botLevel = max(1, min(PowerUpStats.maxLevel, 1 + Int(skill * 4)))
            botPowerUps[i].configure(type: botType, level: botLevel)
            // Stagger first think so they don't all fire together.
            botPowerUpThinkTimers[i] = Float.random(in: 1.5...4.0)
        }
    }

    private func clearRaceMarkers() {
        raceMarkersRoot?.removeFromParentNode()
        raceMarkersRoot = nil
        startLineNode = nil
        finishLineNode = nil
    }

    private func placeRaceMarkers() {
        clearRaceMarkers()
        let root = SCNNode()
        root.name = "raceMarkers"
        trackRoot.addChildNode(root)
        raceMarkersRoot = root

        let width = TrackGenerator.trackWidth
        let startY = track.heightField.height(atX: 0, z: 0)
        let start = RaceMarkers.makeLine(atZ: 0, y: startY, width: width, checkered: false)
        root.addChildNode(start)
        startLineNode = start

        let finishY = track.heightField.height(atX: 0, z: finishZ)
        let finish = RaceMarkers.makeLine(atZ: finishZ, y: finishY, width: width, checkered: true)
        root.addChildNode(finish)
        finishLineNode = finish
    }

    private func updateRaceMarkerHeights() {
        if let start = startLineNode {
            let y = track.heightField.height(atX: 0, z: start.position.z)
            start.position.y = y
        }
        if let finish = finishLineNode {
            finish.position.z = finishZ
            let y = track.heightField.height(atX: 0, z: finishZ)
            finish.position.y = y
        }
    }

    private func resetToMenu() {
        input.reset()
        player.applySkin(selectedSkin)
        player.hide()
        hideBots()
        clearRaceMarkers()
        // Menu is its own screen — no biome track behind the UI.
        track.reset(biome: selectedLevel, spawnStarterChunks: false)
        camera.snap(to: SCNVector3(0, 1.2, 0))
        startZ = 0
        runTime = 0
        distance = 0
        displayedDistance = 0
        runCoins = 0
        totalCoins = CoinStore.total
        standings = []
        cameraLockedAtFinish = false
        awaitingPodium = false
        podiumTimer = 0
        pendingPlayerPowerUpActivation = false
        state = .menu
        lastUpdateTime = 0
        playerPowerUp.reset()
        botPowerUps.forEach { $0.reset() }
        publishPlayerPowerUpHUD()
        refreshPowerUpShopState()
    }

    private func eliminate(_ racer: BallController) {
        guard racer.isAlive, !racer.hasFinished else { return }
        racer.eliminate()
    }

    private func finishCameraFocus() -> SCNVector3 {
        let y = track.heightField.height(atX: 0, z: finishZ)
        return SCNVector3(0, y, finishZ)
    }

    private func beginFinishSpectator(playerPlace: Int) {
        guard !awaitingPodium else { return }
        awaitingPodium = true
        cameraLockedAtFinish = true
        finishPlace = playerPlace
        podiumTimer = 0
        let rivalZ = bots
            .filter { $0.isAlive || $0.hasFinished }
            .map(\.position.z)
            .max() ?? player.position.z
        finishLeadMeters = player.position.z - rivalZ
        input.reset()
        camera.snap(to: finishCameraFocus())
    }

    private func endRace(playerPlace: Int) {
        guard state == .playing else { return }
        finishPlace = playerPlace
        BotDifficultyStore.recordResult(place: playerPlace, leadMeters: finishLeadMeters)
        input.reset()
        refreshStandings()
        awaitingPodium = false
        // Keep cameraLockedAtFinish so the finish cam holds through the results screen.
        // Balls keep rolling — do not freeze.
        state = playerPlace == 1 ? .won : .dead
    }

    /// True once every living racer has a finish order (DNFs don't block the podium).
    private func podiumReady() -> Bool {
        let stillRacing = racers.contains { $0.isAlive && !$0.hasFinished }
        return !stillRacing || podiumTimer >= podiumTimeout
    }

    private func currentForwardSpeed() -> Float {
        min(maxSpeed, baseSpeed + runTime * speedRampPerSecond)
    }

    private func refreshStandings() {
        let finished = racers
            .filter(\.hasFinished)
            .sorted {
                (finishOrders[ObjectIdentifier($0)] ?? 99)
                    < (finishOrders[ObjectIdentifier($1)] ?? 99)
            }
        let racing = racers
            .filter { $0.isAlive && !$0.hasFinished }
            .sorted { $0.position.z > $1.position.z }
        let out = racers.filter { !$0.isAlive && !$0.hasFinished }

        var rows: [RaceStanding] = []
        var place = 1
        for racer in finished + racing + out {
            rows.append(
                RaceStanding(
                    id: racer.displayName,
                    name: racer.displayName,
                    place: place,
                    isPlayer: racer.isPlayer,
                    hasFinished: racer.hasFinished,
                    isOut: !racer.isAlive && !racer.hasFinished
                )
            )
            place += 1
        }
        // Skip @Published churn when order hasn't changed (was rebuilding SwiftUI every frame).
        guard rows != standings else { return }
        if Thread.isMainThread {
            standings = rows
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.standings = rows
            }
        }
    }

    private func checkFinishLine() {
        for racer in racers where racer.isAlive && !racer.hasFinished {
            guard racer.position.z >= finishZ else { continue }
            let order = nextFinishOrder
            nextFinishOrder += 1
            finishOrders[ObjectIdentifier(racer)] = order
            // Keep rolling past the line — place is locked, motion continues.
            racer.markFinished()

            if racer.isPlayer {
                beginFinishSpectator(playerPlace: order)
            }
        }
    }

    private func runtime(for racer: BallController) -> PowerUpRuntime? {
        if racer.isPlayer { return playerPowerUp }
        if let index = bots.firstIndex(where: { $0 === racer }) {
            return botPowerUps[index]
        }
        return nil
    }

    private func maybeActivateBotPowerUps(deltaTime: Float) {
        guard !awaitingPodium else { return }
        for i in 0..<bots.count {
            let bot = bots[i]
            guard bot.isAlive, !bot.hasFinished else { continue }
            let runtime = botPowerUps[i]
            guard runtime.hasPowerUp else { continue }

            botPowerUpThinkTimers[i] -= deltaTime
            guard botPowerUpThinkTimers[i] <= 0 else { continue }
            botPowerUpThinkTimers[i] = Float.random(in: 0.35...0.85)

            guard runtime.isReady else { continue }
            guard shouldBotActivate(botIndex: i, runtime: runtime) else { continue }
            guard let activation = runtime.tryActivate() else { continue }
            applyActivationSideEffects(activation, caster: bot)
            playActivationVFX(activation, on: bot)
        }
    }

    private func shouldBotActivate(botIndex: Int, runtime: PowerUpRuntime) -> Bool {
        guard let type = runtime.type else { return false }
        let bot = bots[botIndex]
        let skill = botBrains[botIndex].skill
        // Weaker bots fire less often even when the situation fits.
        let chanceGate = Float.random(in: 0...1)
        guard chanceGate < (0.35 + skill * 0.55) else { return false }

        switch type {
        case .speedBoost:
            let behind = player.position.z - bot.position.z
            return behind > 3 || Float.random(in: 0...1) < 0.12
        case .ghost:
            let blocked = track.obstacles.intersectsBall(
                x: bot.position.x,
                y: bot.position.y,
                z: bot.position.z + 8,
                ballRadius: bot.radius + 0.15
            ) || track.obstacles.intersectsBall(
                x: bot.position.x,
                y: bot.position.y,
                z: bot.position.z + 14,
                ballRadius: bot.radius + 0.15
            )
            return blocked || Float.random(in: 0...1) < 0.08
        case .slowPulse:
            let dx = player.position.x - bot.position.x
            let dz = player.position.z - bot.position.z
            let distSq = dx * dx + dz * dz
            let radius = runtime.stats?.slowRadius ?? 10
            return distSq <= (radius * radius) && player.position.z >= bot.position.z - 2
        case .coinMagnet:
            return false
        }
    }

    private func updatePlaying(deltaTime: Float) {
        runTime += deltaTime
        let speed = currentForwardSpeed()
        let halfWidth = TrackGenerator.trackWidth * 0.5

        processPendingPlayerPowerUpActivation()

        playerPowerUp.tick(deltaTime, isAirborne: player.isAirborne)
        for (index, runtime) in botPowerUps.enumerated() {
            let airborne = index < bots.count ? bots[index].isAirborne : false
            runtime.tick(deltaTime, isAirborne: airborne)
        }
        maybeActivateBotPowerUps(deltaTime: deltaTime)
        publishPlayerPowerUpHUD()

        // Everyone still alive keeps rolling, including racers who already crossed.
        for racer in racers where racer.isAlive {
            let lateral: Float
            var personalSpeed = speed
            let power = runtime(for: racer)
            if racer.isPlayer {
                // After finishing, coast straight so the finish cam stays readable.
                lateral = awaitingPodium ? 0 : input.lateral
            } else if let index = bots.firstIndex(where: { $0 === racer }) {
                let botGhost = power?.isGhost == true
                lateral = botBrains[index].desiredLateral(
                    positionX: racer.position.x,
                    positionZ: racer.position.z,
                    deltaTime: deltaTime,
                    trackHalfWidth: halfWidth,
                    ballRadius: racer.radius,
                    obstacles: track.obstacles,
                    ignoreObstacles: botGhost
                )
                personalSpeed *= botSpeedScales[index]
                let referenceZ = player.hasFinished ? finishZ : player.position.z
                let gap = referenceZ - racer.position.z
                if gap > 4, botCatchUpStrength > 0.01, !racer.hasFinished {
                    personalSpeed *= 1 + min(botCatchUpStrength, gap * botCatchUpStrength * 0.045)
                }
            } else {
                lateral = 0
            }

            let zoneScale = track.slowZones.speedScale(
                atX: racer.position.x,
                z: racer.position.z
            )
            let powerScale = power?.movementSpeedMultiplier(isAirborne: racer.isAirborne) ?? 1
            racer.applyMovement(
                lateral: lateral,
                forwardSpeed: personalSpeed,
                deltaTime: deltaTime,
                trackHalfWidth: halfWidth,
                heightField: track.heightField,
                speedScale: zoneScale * powerScale
            )

            let isGhost = power?.isGhost == true
            if !isGhost {
                racer.resolveSolidObstacles(
                    obstacles: track.obstacles,
                    polarBears: track.polarBears,
                    moose: track.moose,
                    brownBears: track.brownBears,
                    bunnies: track.bunnies,
                    alligators: track.alligators,
                    frogs: track.frogs,
                    lavaLizards: track.lavaLizards,
                    crabs: track.crabs,
                    seaTurtles: track.seaTurtles,
                    trackHalfWidth: halfWidth
                )
            }
            racer.updatePowerUpVFX(
                deltaTime: deltaTime,
                isSpeedBoost: power?.isSpeedBoostActive == true,
                isGhost: isGhost,
                isMagnet: power?.isMagnetActive == true
            )
        }

        track.geysers.updateVisuals(atTime: runTime)
        track.updateWildlife(deltaTime: deltaTime, time: runTime)

        if player.isAlive {
            let magnetReach = playerPowerUp.magnetReach()
            let gained = track.coins.collect(
                atX: player.position.x,
                y: player.position.y,
                z: player.position.z,
                ballRadius: player.radius,
                magnetReach: magnetReach,
                deltaTime: deltaTime
            )
            if gained > 0 {
                runCoins += gained
                CoinStore.add(gained)
                totalCoins = CoinStore.total
                CoinSFX.shared.play(count: gained)
            }
        }

        for racer in racers where racer.isAlive && !racer.hasFinished {
            let pos = racer.position
            if racer.canLaunchFromGeyser,
               let impulse = track.geysers.launchImpulse(
                   atX: pos.x,
                   y: pos.y,
                   z: pos.z,
                   ballRadius: racer.radius,
                   time: runTime
               ) {
                racer.launchFromGeyser(impulse: impulse)
            }

            if pos.y < -1.15 {
                eliminate(racer)
            }
        }

        checkFinishLine()
        if state != .playing { return }

        if !player.isAlive {
            refreshStandings()
            let resolved = standings.first(where: \.isPlayer)?.place ?? racers.count
            let rivalZ = bots
                .filter { $0.isAlive || $0.hasFinished }
                .map(\.position.z)
                .max() ?? player.position.z
            finishLeadMeters = player.position.z - rivalZ
            endRace(playerPlace: resolved)
            return
        }

        if awaitingPodium {
            podiumTimer += deltaTime
            if podiumReady() {
                endRace(playerPlace: finishPlace)
                return
            }
        }

        refreshStandings()

        let racingZs = racers
            .filter(\.isAlive)
            .map(\.position.z)
        let leadZ = racingZs.max() ?? player.position.z
        let trailZ = racingZs.min() ?? (cameraLockedAtFinish ? finishZ - 40 : player.position.z)

        if cameraLockedAtFinish {
            camera.update(following: finishCameraFocus(), deltaTime: deltaTime)
            // Only keep a short strip past the line — don't build kilometers of track while spectating.
            let genLead = min(max(leadZ, finishZ), finishZ + TrackGenerator.chunkLength * 2)
            let genTrail = max(trailZ, finishZ - TrackGenerator.chunkLength * 3)
            track.update(leadZ: genLead, trailZ: genTrail, playerX: 0)
        } else {
            if startupCameraFrames > 0 {
                camera.snap(to: player.position)
                startupCameraFrames -= 1
            } else {
                camera.update(following: player.position, deltaTime: deltaTime)
            }
            track.update(leadZ: leadZ, trailZ: trailZ, playerX: player.position.x)
        }
        updateRaceMarkerHeights()

        let traveled = Int(max(0, min(player.position.z, finishZ) - startZ))
        if traveled != displayedDistance {
            displayedDistance = traveled
            distance = traveled
        }
    }

    /// Keep everyone rolling after the results card appears, with the cam locked on the finish.
    private func updatePostRaceCoast(deltaTime: Float) {
        runTime += deltaTime
        let speed = currentForwardSpeed()
        let halfWidth = TrackGenerator.trackWidth * 0.5

        for racer in racers where racer.isAlive {
            let lateral: Float
            var personalSpeed = speed
            if racer.isPlayer {
                lateral = 0
            } else if let index = bots.firstIndex(where: { $0 === racer }) {
                // Coast mostly forward so AI work stays cheap on the results screen.
                lateral = botBrains[index].desiredLateral(
                    positionX: racer.position.x,
                    positionZ: racer.position.z,
                    deltaTime: deltaTime,
                    trackHalfWidth: halfWidth,
                    ballRadius: racer.radius,
                    obstacles: track.obstacles
                ) * 0.35
                personalSpeed *= botSpeedScales[index]
            } else {
                lateral = 0
            }

            let speedScale = track.slowZones.speedScale(
                atX: racer.position.x,
                z: racer.position.z
            )
            racer.applyMovement(
                lateral: lateral,
                forwardSpeed: personalSpeed,
                deltaTime: deltaTime,
                trackHalfWidth: halfWidth,
                heightField: track.heightField,
                speedScale: speedScale
            )
        }

        track.geysers.updateVisuals(atTime: runTime)
        // No new track / wildlife growth on the results screen — that made Play Again hitch hard.
        camera.update(following: finishCameraFocus(), deltaTime: deltaTime)
    }
}

extension GameSceneController: SCNSceneRendererDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt: Float
        if lastUpdateTime == 0 {
            dt = 1.0 / 60.0
        } else {
            // Soft cap: allow catching up a bit after hitch frames so the ball
            // doesn't crawl when FPS briefly dips below 20.
            dt = Float(min(time - lastUpdateTime, 1.0 / 12.0))
        }
        lastUpdateTime = time

        switch state {
        case .playing:
            updatePlaying(deltaTime: dt)
        case .won, .dead:
            if cameraLockedAtFinish {
                updatePostRaceCoast(deltaTime: dt)
            }
        default:
            break
        }
    }
}
