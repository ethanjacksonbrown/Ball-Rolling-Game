import SceneKit
import UIKit

final class TrackGenerator {
    static let chunkLength: Float = 28
    /// Wide playable land so biomes feel like areas, not a narrow strip.
    static let trackWidth: Float = 46
    static let safeChunkCount = 2
    /// How far water / scenery extends outward from each path edge (fills the view).
    static let waterExtent: CGFloat = 160
    /// Sand shelf beyond each beach path edge — part of the same ground mesh.
    static let tropicalSideExtent: Float = 28

    let heightField = HeightField()
    let obstacles = ObstacleIndex()
    let slowZones = SlowZoneIndex()
    let geysers = GeyserIndex()
    let icePatches = IcePatchIndex()
    let polarBears = PolarBearIndex()
    let moose = MooseIndex()
    let brownBears = BrownBearIndex()
    let bunnies = BunnyIndex()
    let alligators = AlligatorIndex()
    let frogs = FrogIndex()
    let lavaLizards = LavaLizardIndex()
    let crabs = CrabIndex()
    let seaTurtles = SeaTurtleIndex()
    let coins = CoinIndex()

    private weak var rootNode: SCNNode?
    private var chunks: [SCNNode] = []
    private var nextChunkZ: Float = -8
    private var chunksSpawned = 0
    private var activeBiome: Biome = .swamp
    /// If set, the next spawned chunk blends ground from this biome into `activeBiome`.
    private var blendFromBiome: Biome?
    /// Multi-chunk water color blend (lava ↔ blue looked banded with single-chunk UV planes).
    private var waterBlendFrom: Biome?
    private var waterBlendStepsRemaining = 0
    private var chunksInCurrentBiome = 0
    /// ~2.5–3× the old 8-chunk biome length.
    private var currentBiomeLength = 22
    private var rng = SystemRandomNumberGenerator()
    private var raisedZones: [(start: Float, end: Float)] = []
    private var blockedFootprints: [(startZ: Float, endZ: Float, minX: Float, maxX: Float)] = []
    init(rootNode: SCNNode) {
        self.rootNode = rootNode
    }

    func reset() {
        reset(biome: .forest)
    }

    /// Rebuild the track locked to a single biome for the whole run.
    /// Pass `spawnStarterChunks: false` for the menu (no biome preview).
    func reset(biome: Biome, spawnStarterChunks: Bool = true) {
        chunks.forEach { $0.removeFromParentNode() }
        chunks.removeAll()
        heightField.reset()
        obstacles.reset()
        slowZones.reset()
        geysers.reset()
        icePatches.reset()
        polarBears.reset()
        moose.reset()
        brownBears.reset()
        bunnies.reset()
        alligators.reset()
        frogs.reset()
        lavaLizards.reset()
        crabs.reset()
        seaTurtles.reset()
        coins.reset()
        nextChunkZ = -8
        chunksSpawned = 0
        blendFromBiome = nil
        waterBlendFrom = nil
        waterBlendStepsRemaining = 0
        chunksInCurrentBiome = 0
        rng = SystemRandomNumberGenerator()
        activeBiome = biome
        currentBiomeLength = Int.max
        guard spawnStarterChunks else { return }
        // A short starter strip; the rest streams in during the first frames of play.
        for _ in 0..<3 {
            spawnNextChunk()
        }
    }

    func update(leadZ: Float, trailZ: Float, playerX: Float) {
        let spawnCap = leadZ + Self.chunkLength * 3
        while nextChunkZ < spawnCap {
            spawnNextChunk()
        }

        // Never cull past the slowest racer — otherwise leaders unload the track under the pack.
        let cullZ = trailZ - Self.chunkLength * 2.5
        heightField.cull(beforeZ: cullZ)
        obstacles.cull(beforeZ: cullZ)
        slowZones.cull(beforeZ: cullZ)
        geysers.cull(beforeZ: cullZ)
        icePatches.cull(beforeZ: cullZ)
        polarBears.cull(beforeZ: cullZ)
        moose.cull(beforeZ: cullZ)
        brownBears.cull(beforeZ: cullZ)
        bunnies.cull(beforeZ: cullZ)
        alligators.cull(beforeZ: cullZ)
        frogs.cull(beforeZ: cullZ)
        lavaLizards.cull(beforeZ: cullZ)
        crabs.cull(beforeZ: cullZ)
        seaTurtles.cull(beforeZ: cullZ)
        coins.cull(beforeZ: cullZ)

        chunks.removeAll { chunk in
            guard let z = chunk.value(forKeyPath: "chunkEndZ") as? Float else { return false }
            if z < cullZ {
                chunk.removeFromParentNode()
                return true
            }
            return false
        }
    }

    func updateWildlife(deltaTime: Float, time: Float) {
        polarBears.update(
            deltaTime: deltaTime,
            time: time,
            ice: icePatches,
            heightField: heightField,
            trackHalfWidth: Self.trackWidth * 0.5
        )
        moose.update(
            deltaTime: deltaTime,
            ice: icePatches,
            heightField: heightField,
            trackHalfWidth: Self.trackWidth * 0.5
        )
        brownBears.update(
            deltaTime: deltaTime,
            heightField: heightField,
            trackHalfWidth: Self.trackWidth * 0.5
        )
        bunnies.update(
            deltaTime: deltaTime,
            heightField: heightField,
            trackHalfWidth: Self.trackWidth * 0.5
        )
        alligators.update(
            deltaTime: deltaTime,
            heightField: heightField,
            trackHalfWidth: Self.trackWidth * 0.5
        )
        frogs.update(
            deltaTime: deltaTime,
            heightField: heightField,
            trackHalfWidth: Self.trackWidth * 0.5
        )
        lavaLizards.update(
            deltaTime: deltaTime,
            heightField: heightField,
            trackHalfWidth: Self.trackWidth * 0.5
        )
        crabs.update(
            deltaTime: deltaTime,
            heightField: heightField,
            trackHalfWidth: Self.trackWidth * 0.5
        )
        seaTurtles.update(
            deltaTime: deltaTime,
            heightField: heightField,
            trackHalfWidth: Self.trackWidth * 0.5
        )
    }

    private func spawnNextChunk() {
        let startZ = nextChunkZ
        let endZ = startZ + Self.chunkLength
        let container = SCNNode()
        container.name = "chunk"
        container.setValue(endZ, forKey: "chunkEndZ")
        raisedZones = []
        blockedFootprints = []

        let fromBiome = blendFromBiome ?? activeBiome
        let toBiome = activeBiome
        blendFromBiome = nil

        let waterFromColor: UIColor
        let waterToColor: UIColor
        if waterBlendStepsRemaining > 0, let origin = waterBlendFrom {
            let totalSteps = 2
            let stepIndex = totalSteps - waterBlendStepsRemaining
            let t0 = CGFloat(stepIndex) / CGFloat(totalSteps)
            let t1 = CGFloat(stepIndex + 1) / CGFloat(totalSteps)
            waterFromColor = GameArt.lerpColor(origin.waterSurfaceColor, activeBiome.waterSurfaceColor, t: t0)
            waterToColor = GameArt.lerpColor(origin.waterSurfaceColor, activeBiome.waterSurfaceColor, t: t1)
            waterBlendStepsRemaining -= 1
            if waterBlendStepsRemaining == 0 {
                waterBlendFrom = nil
            }
        } else {
            waterFromColor = activeBiome.waterSurfaceColor
            waterToColor = activeBiome.waterSurfaceColor
        }

        let allowFeatures = chunksSpawned >= Self.safeChunkCount

        var jumpLandingZ: Float?
        if allowFeatures {
            jumpLandingZ = addTerrainFeatures(
                startZ: startZ,
                endZ: endZ,
                biome: toBiome
            )
        }

        // One continuous ground mesh so hills and flat grass share the same surface/shading.
        addChunkGround(to: container, startZ: startZ, from: fromBiome, to: toBiome)
        let waterPathWidth = (fromBiome == .tropical || toBiome == .tropical)
            ? Self.trackWidth + Self.tropicalSideExtent * 2
            : Self.trackWidth
        addEdgeWater(
            to: container,
            startZ: startZ,
            pathWidth: waterPathWidth,
            length: Self.chunkLength,
            fromColor: waterFromColor,
            toColor: waterToColor
        )
        addBiomeEdgeScenery(
            to: container,
            startZ: startZ,
            endZ: endZ,
            biome: toBiome
        )

        if allowFeatures {
            if toBiome == .lava {
                let pockets = addLavaPockets(to: container, startZ: startZ, endZ: endZ)
                lavaLizards.registerPockets(pockets, chunkEndZ: endZ)
                if let root = rootNode {
                    lavaLizards.maybeSpawn(
                        aroundZ: startZ + Self.chunkLength * 0.5,
                        parent: root,
                        heightField: heightField,
                        trackHalfWidth: Self.trackWidth * 0.5,
                        pockets: pockets
                    )
                }
            }

            // Ponds first in swamp so willow clusters can stand in the water.
            var swampPonds: [(x: Float, z: Float, radius: Float, surfaceY: Float)] = []
            if toBiome == .swamp {
                swampPonds = addSwampPonds(to: container, startZ: startZ, endZ: endZ)
                let pondSpots = swampPonds.map { (x: $0.x, z: $0.z, radius: $0.radius) }
                alligators.registerPonds(pondSpots, chunkEndZ: endZ)
                frogs.registerPonds(pondSpots, chunkEndZ: endZ)
                if let root = rootNode {
                    alligators.maybeSpawn(
                        aroundZ: startZ + Self.chunkLength * 0.5,
                        parent: root,
                        heightField: heightField,
                        trackHalfWidth: Self.trackWidth * 0.5,
                        ponds: pondSpots
                    )
                    frogs.maybeSpawn(
                        aroundZ: startZ + Self.chunkLength * 0.5,
                        parent: root,
                        heightField: heightField,
                        trackHalfWidth: Self.trackWidth * 0.5,
                        ponds: pondSpots
                    )
                }
            }
            placeObstaclesAndTrees(
                on: container,
                startZ: startZ,
                endZ: endZ,
                biome: toBiome,
                jumpLandingZ: jumpLandingZ,
                swampPonds: swampPonds
            )
            placeCoins(on: container, startZ: startZ, endZ: endZ)
            if toBiome == .snow {
                addSnowIce(to: container, startZ: startZ, endZ: endZ)
                if let root = rootNode {
                    polarBears.maybeSpawn(
                        aroundZ: startZ + Self.chunkLength * 0.5,
                        parent: root,
                        ice: icePatches,
                        heightField: heightField,
                        trackHalfWidth: Self.trackWidth * 0.5
                    )
                    moose.maybeSpawn(
                        aroundZ: startZ + Self.chunkLength * 0.5,
                        parent: root,
                        ice: icePatches,
                        heightField: heightField,
                        trackHalfWidth: Self.trackWidth * 0.5
                    )
                }
            }
            if toBiome == .forest, let root = rootNode {
                brownBears.maybeSpawn(
                    aroundZ: startZ + Self.chunkLength * 0.5,
                    parent: root,
                    heightField: heightField,
                    trackHalfWidth: Self.trackWidth * 0.5
                )
                bunnies.maybeSpawn(
                    aroundZ: startZ + Self.chunkLength * 0.5,
                    parent: root,
                    heightField: heightField,
                    trackHalfWidth: Self.trackWidth * 0.5
                )
            }
            if toBiome == .tropical, let root = rootNode {
                crabs.maybeSpawn(
                    aroundZ: startZ + Self.chunkLength * 0.5,
                    parent: root,
                    heightField: heightField,
                    trackHalfWidth: Self.trackWidth * 0.5
                )
                seaTurtles.maybeSpawn(
                    aroundZ: startZ + Self.chunkLength * 0.5,
                    parent: root,
                    heightField: heightField,
                    trackHalfWidth: Self.trackWidth * 0.5
                )
            }
            if toBiome == .lava {
                addLavaGeysers(to: container, startZ: startZ, endZ: endZ)
            }
        }

        // Stay in the selected level biome for the entire run — no mid-run transitions.
        if chunksSpawned > 0 {
            chunksInCurrentBiome += 1
        }

        rootNode?.addChildNode(container)
        chunks.append(container)
        nextChunkZ = endZ
        chunksSpawned += 1
    }

    private func addChunkGround(to container: SCNNode, startZ: Float, from: Biome, to: Biome) {
        let material = GameArt.groundMaterial(from: from, to: to)
        let beachSides = from == .tropical || to == .tropical
        let sideExtent = beachSides ? Self.tropicalSideExtent : 0
        let totalWidth = Self.trackWidth + sideExtent * 2
        let halfPath = Self.trackWidth * 0.5
        let node = SmoothTerrain.makeChunkGround(
            width: totalWidth,
            length: Self.chunkLength,
            worldStartZ: startZ,
            material: material,
            segmentsZ: beachSides ? 32 : 28,
            segmentsX: beachSides ? 40 : 22,
            heightAt: { [heightField] x, z in
                if abs(x) <= halfPath {
                    return heightField.height(atX: x, z: z)
                }
                // Beach dunes live in this same mesh — no stacked side strips.
                return Self.tropicalDuneHeight(worldX: x, worldZ: z)
            }
        )
        container.addChildNode(node)
    }

    /// Deterministic side-dune height from world position so chunk seams match.
    private static func tropicalDuneHeight(worldX: Float, worldZ: Float) -> Float {
        let halfPath = trackWidth * 0.5
        let side = tropicalSideExtent
        let ax = abs(worldX)
        guard ax > halfPath else { return 0 }

        let u = min(1, (ax - halfPath) / side)
        // Soft rolls from world Z/X — continuous across chunk boundaries.
        let ridgeA = (0.55 + 0.45 * sin(worldZ * 0.105)) * 1.65
        let ridgeB = (0.55 + 0.45 * sin(worldZ * 0.185 + 1.35)) * 1.0
        let ridgeC = (0.55 + 0.45 * sin(worldZ * 0.068 + 2.2)) * 0.7
        let acrossWave = 0.72 + 0.28 * sin(worldX * 0.20 + worldZ * 0.04)
        let across = sin(Float.pi * max(0.1, min(0.9, u)))
        let outerFade = 1 - pow(max(0, u - 0.84) / 0.16, 1.55)
        let pathBlend = pow(min(1, u / 0.09), 0.55)
        let dunes = (ridgeA + ridgeB + ridgeC) * across * acrossWave * outerFade * pathBlend
        // Blend from track level (0) at the path edge so there is no lip seam.
        return max(0, dunes)
    }

    private func addTerrainFeatures(
        startZ: Float,
        endZ: Float,
        biome: Biome
    ) -> Float? {
        _ = endZ
        _ = biome

        let localCount = Int.random(in: 1...3, using: &rng)
        for _ in 0..<localCount {
            if Float.random(in: 0...1, using: &rng) < 0.75 {
                addLocalMound(startZ: startZ)
            }
        }

        // One or two separate natural hills — never a full-width shelf.
        let hillCount = Int.random(in: 0...2, using: &rng)
        for _ in 0..<hillCount {
            if Float.random(in: 0...1, using: &rng) < 0.7 {
                addNaturalHill(startZ: startZ, endZ: endZ)
            }
        }

        if Float.random(in: 0...1, using: &rng) < 0.28 {
            addDivot(startZ: startZ)
        }
        if Float.random(in: 0...1, using: &rng) < 0.12 {
            addDivot(startZ: startZ)
        }

        return nil
    }

    private func addLocalMound(startZ: Float) {
        let width = Float.random(in: 4.5...9.0, using: &rng)
        let length = Float.random(in: 5.0...11.0, using: &rng)
        let peak = Float.random(in: 0.28...0.95, using: &rng)
        let centerX = Float.random(
            in: (-Self.trackWidth * 0.38)...(Self.trackWidth * 0.38),
            using: &rng
        )
        let moundStart = startZ + Float.random(in: 3...(Self.chunkLength - length - 2), using: &rng)
        if isBlocked(x: centerX, z: moundStart + length * 0.5) { return }

        let halfW = width * 0.5
        let localProfile = TerrainProfiles.localMound(peak: peak, halfWidth: halfW)
        heightField.addBand(
            startZ: moundStart,
            length: length,
            minX: centerX - halfW,
            maxX: centerX + halfW,
            heightAt: { worldX, t in localProfile(worldX - centerX, t) }
        )
    }

    private func addNaturalHill(startZ: Float, endZ: Float) {
        _ = endZ
        let width = Float.random(in: 8.0...15.0, using: &rng)
        let length = Float.random(in: 10.0...16.0, using: &rng)
        let peak = Float.random(in: 1.8...3.4, using: &rng)
        let margin = width * 0.55
        let centerX = Float.random(
            in: (-Self.trackWidth * 0.5 + margin)...(Self.trackWidth * 0.5 - margin),
            using: &rng
        )
        let hillStart = startZ + Float.random(in: 3...(Self.chunkLength - length - 2), using: &rng)
        if isBlocked(x: centerX, z: hillStart + length * 0.5) { return }

        let halfW = width * 0.5
        let minX = centerX - halfW
        let maxX = centerX + halfW
        let profile = TerrainProfiles.naturalHill(peak: peak, halfWidth: halfW)

        heightField.addBand(
            startZ: hillStart,
            length: length,
            minX: minX,
            maxX: maxX,
            heightAt: { worldX, t in profile(worldX - centerX, t) }
        )
        blockedFootprints.append((hillStart, hillStart + length, minX, maxX))
    }

    private func addDivot(startZ: Float) {
        let length = Float.random(in: 4...7, using: &rng)
        let width = Float.random(in: 5...10, using: &rng)
        let depth = Float.random(in: 0.35...0.75, using: &rng)
        let centerX = Float.random(
            in: (-Self.trackWidth * 0.35)...(Self.trackWidth * 0.35),
            using: &rng
        )
        let divotStart = startZ + Float.random(in: 4...(Self.chunkLength - length - 3), using: &rng)
        if isBlocked(x: centerX, z: divotStart + length * 0.5) { return }

        let halfW = width * 0.5
        let profile = TerrainProfiles.divotBowl(depth: depth, halfWidth: halfW)
        heightField.addBand(
            startZ: divotStart,
            length: length,
            minX: centerX - halfW,
            maxX: centerX + halfW,
            isDip: true,
            heightAt: { worldX, t in profile(worldX - centerX, t) }
        )
    }

    @discardableResult
    private func addSwampPonds(
        to container: SCNNode,
        startZ: Float,
        endZ: Float
    ) -> [(x: Float, z: Float, radius: Float, surfaceY: Float)] {
        var ponds: [(x: Float, z: Float, radius: Float, surfaceY: Float)] = []
        // Twice the old density — still leave gaps so the path isn't one slow carpet.
        let pondCount = Int.random(in: 2...4, using: &rng)
        var attempts = 0
        while ponds.count < pondCount && attempts < 28 {
            attempts += 1
            let radius = Float.random(in: 1.6...2.8, using: &rng)
            let x: Float
            let z: Float
            // Bias later ponds toward existing water so swampy clusters form.
            if let anchor = ponds.randomElement(using: &rng), Float.random(in: 0...1, using: &rng) < 0.55 {
                x = anchor.x + Float.random(in: -7...7, using: &rng)
                z = anchor.z + Float.random(in: -7...7, using: &rng)
                if abs(x) > Self.trackWidth * 0.36 { continue }
                if z < startZ + 4 || z > endZ - 4 { continue }
            } else {
                x = Float.random(in: (-Self.trackWidth * 0.34)...(Self.trackWidth * 0.34), using: &rng)
                z = startZ + Float.random(in: 4...(Self.chunkLength - 4), using: &rng)
            }
            if isBlocked(x: x, z: z) { continue }

            let tooClose = ponds.contains {
                hypot(x - $0.x, z - $0.z) < ($0.radius + radius + 2.2)
            }
            if tooClose { continue }

            let surfaceY = heightField.height(atX: x, z: z) + 0.04
            let water = SCNCylinder(radius: CGFloat(radius), height: 0.1)
            water.radialSegmentCount = 16
            water.firstMaterial = GameArt.pondMaterial()
            let node = SCNNode(geometry: water)
            node.position = SCNVector3(x, surfaceY, z)
            node.castsShadow = false
            container.addChildNode(node)

            slowZones.add(
                SlowZone(
                    minX: x - radius,
                    maxX: x + radius,
                    startZ: z - radius,
                    endZ: z + radius,
                    speedScale: 0.62,
                    chunkEndZ: endZ
                )
            )
            ponds.append((x, z, radius, surfaceY))
        }
        return ponds
    }

    private func addSnowIce(to container: SCNNode, startZ: Float, endZ: Float) {
        // Slightly denser patches so bears have ice clusters to prefer.
        let patchCount = Int.random(in: 2...4, using: &rng)
        var placed: [(x: Float, z: Float, radius: Float)] = []
        for _ in 0..<patchCount {
            let radius = Float.random(in: 2.4...4.6, using: &rng)
            // Bias later patches toward existing ice so clusters form.
            let x: Float
            let z: Float
            if let anchor = placed.randomElement(using: &rng), Float.random(in: 0...1, using: &rng) < 0.55 {
                x = anchor.x + Float.random(in: -6...6, using: &rng)
                z = anchor.z + Float.random(in: -6...6, using: &rng)
                if abs(x) > Self.trackWidth * 0.38 { continue }
                if z < startZ + 4 || z > endZ - 4 { continue }
            } else {
                x = Float.random(in: (-Self.trackWidth * 0.36)...(Self.trackWidth * 0.36), using: &rng)
                z = startZ + Float.random(in: 5...(Self.chunkLength - 5), using: &rng)
            }
            if isBlocked(x: x, z: z) { continue }

            let surfaceY = heightField.height(atX: x, z: z) + 0.035
            let ice = SCNCylinder(radius: CGFloat(radius), height: 0.09)
            ice.radialSegmentCount = 20
            ice.firstMaterial = GameArt.iceMaterial()
            let node = SCNNode(geometry: ice)
            node.position = SCNVector3(x, surfaceY, z)
            node.castsShadow = false
            container.addChildNode(node)

            slowZones.add(
                SlowZone(
                    minX: x - radius,
                    maxX: x + radius,
                    startZ: z - radius,
                    endZ: z + radius,
                    speedScale: Float.random(in: 1.35...1.55, using: &rng),
                    chunkEndZ: endZ
                )
            )
            icePatches.add(IcePatch(x: x, z: z, radius: radius, chunkEndZ: endZ))
            placed.append((x, z, radius))
        }
    }

    private func addLavaGeysers(to container: SCNNode, startZ: Float, endZ: Float) {
        let count = Int.random(in: 1...3, using: &rng)
        var placed: [(x: Float, z: Float)] = []
        var attempts = 0
        while placed.count < count && attempts < 14 {
            attempts += 1
            let x = Float.random(in: (-Self.trackWidth * 0.38)...(Self.trackWidth * 0.38), using: &rng)
            let z = startZ + Float.random(in: 5...(Self.chunkLength - 5), using: &rng)
            if isBlocked(x: x, z: z) || isTooSteep(x: x, z: z) { continue }
            let tooClose = placed.contains { hypot(x - $0.x, z - $0.z) < 5.5 }
            if tooClose { continue }

            let baseY = heightField.height(atX: x, z: z)
            let visual = ObstacleFactory.makeLavaGeyser(at: SCNVector3(x, baseY, z))
            container.addChildNode(visual.node)
            geysers.add(
                GeyserVolume(
                    x: x,
                    z: z,
                    baseY: baseY,
                    radius: visual.radius,
                    jetHeight: visual.jetHeight,
                    chunkEndZ: endZ,
                    cycleDuration: Float.random(in: 8.5...11.5, using: &rng),
                    eruptDuration: Float.random(in: 4.8...5.4, using: &rng),
                    phaseOffset: Float.random(in: 0...6.0, using: &rng),
                    jetNode: visual.jetNode,
                    sprayNode: visual.sprayNode,
                    glowNode: visual.glowNode
                )
            )
            blockedFootprints.append((z - 1.4, z + 1.4, x - 1.4, x + 1.4))
            placed.append((x, z))
        }
    }

    private func placeObstaclesAndTrees(
        on container: SCNNode,
        startZ: Float,
        endZ: Float,
        biome: Biome,
        jumpLandingZ: Float?,
        swampPonds: [(x: Float, z: Float, radius: Float, surfaceY: Float)] = []
    ) {
        // Lava gets roughly 2× the usual obstacle/rock scatter.
        let count = biome == .lava
            ? Int.random(in: 4...8, using: &rng)
            : Int.random(in: 2...4, using: &rng)
        for _ in 0..<count {
            let x = Float.random(in: (-Self.trackWidth * 0.4)...(Self.trackWidth * 0.4), using: &rng)
            let z = startZ + Float.random(in: 5...(Self.chunkLength - 4), using: &rng)
            if isBlocked(x: x, z: z) || isTooSteep(x: x, z: z) { continue }
            let baseY = heightField.height(atX: x, z: z)
            placeObstacle(on: container, x: x, z: z, endZ: endZ, biome: biome, baseY: baseY)
        }

        // Props on localized natural hills.
        for band in blockedFootprints {
            let span = band.maxX - band.minX
            guard span >= 7, span <= 17 else { continue }
            let topCount = Int.random(in: 0...2, using: &rng)
            let ridgeStart = band.startZ + (band.endZ - band.startZ) * 0.30
            let ridgeEnd = band.startZ + (band.endZ - band.startZ) * 0.65
            for _ in 0..<topCount {
                let x = Float.random(in: (band.minX + 1.4)...(band.maxX - 1.4), using: &rng)
                let z = Float.random(in: (ridgeStart + 0.5)...(ridgeEnd - 0.5), using: &rng)
                // Hill footprint is intentionally ignored here, but still avoid other props.
                if isTooSteep(x: x, z: z) || obstacles.isNear(x: x, z: z) { continue }
                let baseY = heightField.height(atX: x, z: z)
                placeObstacle(on: container, x: x, z: z, endZ: endZ, biome: biome, baseY: baseY)
            }
        }

        if biome == .forest {
            // Moderate forest cover — dense enough to read as woods, not a wall.
            for _ in 0..<Int.random(in: 5...9, using: &rng) {
                let x = Float.random(in: (-Self.trackWidth * 0.44)...(Self.trackWidth * 0.44), using: &rng)
                let z = startZ + Float.random(in: 3...(Self.chunkLength - 3), using: &rng)
                if isBlocked(x: x, z: z) || isTooSteep(x: x, z: z) { continue }
                let baseY = heightField.height(atX: x, z: z)
                placeObstacle(
                    on: container,
                    x: x,
                    z: z,
                    endZ: endZ,
                    biome: .forest,
                    baseY: baseY,
                    forceTree: true
                )
            }
            // Occasional small groves.
            for _ in 0..<Int.random(in: 1...2, using: &rng) {
                let cx = Float.random(in: (-Self.trackWidth * 0.4)...(Self.trackWidth * 0.4), using: &rng)
                let cz = startZ + Float.random(in: 4...(Self.chunkLength - 4), using: &rng)
                if isBlocked(x: cx, z: cz) { continue }
                for _ in 0..<Int.random(in: 2...4, using: &rng) {
                    let x = cx + Float.random(in: -2.2...2.2, using: &rng)
                    let z = cz + Float.random(in: -2.2...2.2, using: &rng)
                    if abs(x) > Self.trackWidth * 0.45 { continue }
                    if isBlocked(x: x, z: z) || isTooSteep(x: x, z: z) { continue }
                    let baseY = heightField.height(atX: x, z: z)
                    placeObstacle(
                        on: container,
                        x: x,
                        z: z,
                        endZ: endZ,
                        biome: .forest,
                        baseY: baseY,
                        forceTree: true
                    )
                }
            }

            // Decorative bushes — visual only, no collision.
            placeForestBushes(on: container, startZ: startZ, endZ: endZ)
        }

        if biome == .swamp {
            placeSwampWillowClusters(
                on: container,
                startZ: startZ,
                endZ: endZ,
                ponds: swampPonds
            )
        }

        if biome == .snow {
            for _ in 0..<Int.random(in: 2...4, using: &rng) {
                let x = Float.random(in: (-Self.trackWidth * 0.42)...(Self.trackWidth * 0.42), using: &rng)
                let z = startZ + Float.random(in: 4...(Self.chunkLength - 3), using: &rng)
                if isBlocked(x: x, z: z) || isTooSteep(x: x, z: z) { continue }
                let baseY = heightField.height(atX: x, z: z)
                placeObstacle(
                    on: container,
                    x: x,
                    z: z,
                    endZ: endZ,
                    biome: .snow,
                    baseY: baseY,
                    forceTree: true
                )
            }
        }

        if biome == .tropical {
            for _ in 0..<Int.random(in: 2...4, using: &rng) {
                let x = Float.random(in: (-Self.trackWidth * 0.42)...(Self.trackWidth * 0.42), using: &rng)
                let z = startZ + Float.random(in: 4...(Self.chunkLength - 3), using: &rng)
                if isBlocked(x: x, z: z) || isTooSteep(x: x, z: z) { continue }
                let baseY = heightField.height(atX: x, z: z)
                placeObstacle(
                    on: container,
                    x: x,
                    z: z,
                    endZ: endZ,
                    biome: .tropical,
                    baseY: baseY,
                    forceTree: true
                )
            }
        }

        if let landingZ = jumpLandingZ, landingZ < startZ + Self.chunkLength - 2 {
            let rockCount = Int.random(in: 1...2, using: &rng)
            for i in 0..<rockCount {
                let x = Float.random(in: -5...5, using: &rng)
                let z = landingZ + Float(i) * 1.8
                if isBlocked(x: x, z: z) || isTooSteep(x: x, z: z) { continue }
                let size = CGFloat.random(in: 0.55...0.95, using: &rng)
                let baseY = heightField.height(atX: x, z: z)
                let placed = ObstacleFactory.makeRock(
                    at: SCNVector3(x, baseY, z),
                    sizeRange: size...size
                )
                container.addChildNode(placed.node)
                obstacles.add(
                    ObstacleVolume(
                        x: x,
                        z: z,
                        radius: placed.radius,
                        baseY: baseY,
                        height: placed.height,
                        chunkEndZ: endZ
                    )
                )
            }
        }
    }

    /// Bigger forest bushes — scattered singles plus occasional large thickets.
    private func placeForestBushes(on container: SCNNode, startZ: Float, endZ: Float) {
        func placeBush(atX x: Float, z: Float, big: Bool) {
            if abs(x) > Self.trackWidth * 0.45 { return }
            if isBlocked(x: x, z: z) || isTooSteep(x: x, z: z) { return }
            // Bushes can sit closer than solid trees since they have no collision.
            if obstacles.isNear(x: x, z: z, minSeparation: 1.1) { return }
            let baseY = heightField.height(atX: x, z: z)
            let berries = Float.random(in: 0...1, using: &rng) < 0.55
            let scale: ClosedRange<Float> = big ? 1.09...1.61 : 0.86...1.31
            let bush = ObstacleFactory.makeBush(
                at: SCNVector3(x, baseY, z),
                scaleRange: scale,
                withBerries: berries
            )
            container.addChildNode(bush)
        }

        // Scattered larger bushes across the chunk.
        for _ in 0..<Int.random(in: 8...14, using: &rng) {
            let x = Float.random(in: (-Self.trackWidth * 0.44)...(Self.trackWidth * 0.44), using: &rng)
            let z = startZ + Float.random(in: 2...(Self.chunkLength - 2), using: &rng)
            placeBush(atX: x, z: z, big: Float.random(in: 0...1, using: &rng) < 0.55)
        }

        // Large thickets — packs of bushes packed close together.
        let clusterCount = Int.random(in: 1...3, using: &rng)
        for _ in 0..<clusterCount {
            let cx = Float.random(in: (-Self.trackWidth * 0.4)...(Self.trackWidth * 0.4), using: &rng)
            let cz = startZ + Float.random(in: 3...(Self.chunkLength - 3), using: &rng)
            if isBlocked(x: cx, z: cz) { continue }
            let bushesInCluster = Int.random(in: 5...10, using: &rng)
            for _ in 0..<bushesInCluster {
                let x = cx + Float.random(in: -3.2...3.2, using: &rng)
                let z = cz + Float.random(in: -3.2...3.2, using: &rng)
                placeBush(atX: x, z: z, big: Float.random(in: 0...1, using: &rng) < 0.7)
            }
        }
    }

    /// Willow groups — heavily biased to cluster around dense pond water.
    private func placeSwampWillowClusters(
        on container: SCNNode,
        startZ: Float,
        endZ: Float,
        ponds: [(x: Float, z: Float, radius: Float, surfaceY: Float)]
    ) {
        // More clusters when the chunk is watery.
        let clusterCount = ponds.count >= 3
            ? Int.random(in: 3...5, using: &rng)
            : Int.random(in: 2...4, using: &rng)

        for _ in 0..<clusterCount {
            // Usually plant beside ponds; rarely a dry-land grove.
            let usePond = !ponds.isEmpty && Float.random(in: 0...1, using: &rng) < 0.82
            let centerX: Float
            let centerZ: Float
            let pond: (x: Float, z: Float, radius: Float, surfaceY: Float)?

            if usePond, let pick = Self.pickWateryPond(from: ponds, rng: &rng) {
                pond = pick
                // Sit beside the pond more than in the middle of it.
                let side = Float.random(in: 0...(Float.pi * 2), using: &rng)
                let dist = pick.radius + Float.random(in: 0.3...1.8, using: &rng)
                centerX = pick.x + cos(side) * dist
                centerZ = pick.z + sin(side) * dist
            } else {
                pond = nil
                centerX = Float.random(in: (-Self.trackWidth * 0.38)...(Self.trackWidth * 0.38), using: &rng)
                centerZ = startZ + Float.random(in: 4...(Self.chunkLength - 4), using: &rng)
            }

            if abs(centerX) > Self.trackWidth * 0.42 { continue }
            if isBlocked(x: centerX, z: centerZ) { continue }

            let treesInCluster = pond != nil
                ? Int.random(in: 3...5, using: &rng)
                : Int.random(in: 2...3, using: &rng)
            var waterTreesPlaced = 0
            for _ in 0..<treesInCluster {
                let ox = centerX + Float.random(in: -2.2...2.2, using: &rng)
                let oz = centerZ + Float.random(in: -2.2...2.2, using: &rng)
                if abs(ox) > Self.trackWidth * 0.44 { continue }
                if isBlocked(x: ox, z: oz) || isTooSteep(x: ox, z: oz) { continue }

                var inWater = false
                var baseY = heightField.height(atX: ox, z: oz)
                if let pond,
                   waterTreesPlaced < 3,
                   hypot(ox - pond.x, oz - pond.z) < pond.radius * 0.85,
                   Float.random(in: 0...1, using: &rng) < 0.55 {
                    inWater = true
                    baseY = pond.surfaceY
                    waterTreesPlaced += 1
                }

                let placed = ObstacleFactory.makeWillowTree(
                    at: SCNVector3(ox, baseY, oz),
                    inWater: inWater
                )
                container.addChildNode(placed.node)
                obstacles.add(
                    ObstacleVolume(
                        x: ox,
                        z: oz,
                        radius: placed.radius,
                        baseY: baseY,
                        height: placed.height,
                        chunkEndZ: endZ
                    )
                )
            }
        }
    }

    /// Prefer ponds that already sit near other water (denser swamp pockets).
    private static func pickWateryPond(
        from ponds: [(x: Float, z: Float, radius: Float, surfaceY: Float)],
        rng: inout some RandomNumberGenerator
    ) -> (x: Float, z: Float, radius: Float, surfaceY: Float)? {
        guard !ponds.isEmpty else { return nil }
        var best = ponds[0]
        var bestScore: Float = -1
        for pond in ponds {
            var neighbors: Float = 0
            for other in ponds where other.x != pond.x || other.z != pond.z {
                let d = hypot(pond.x - other.x, pond.z - other.z)
                if d < pond.radius + other.radius + 10 {
                    neighbors += 1 + max(0, 1 - d / 12)
                }
            }
            let score = neighbors + Float.random(in: 0...0.35, using: &rng)
            if score > bestScore {
                bestScore = score
                best = pond
            }
        }
        // Still allow a random pick sometimes so every pond can get trees.
        if Float.random(in: 0...1, using: &rng) < 0.25 {
            return ponds.randomElement(using: &rng)
        }
        return best
    }

    private func placeObstacle(
        on container: SCNNode,
        x: Float,
        z: Float,
        endZ: Float,
        biome: Biome,
        baseY: Float,
        forceTree: Bool = false
    ) {
        // Final guard — callers usually check, but hill / grove paths can still collide.
        guard !obstacles.isNear(x: x, z: z) else { return }

        let position = SCNVector3(x, baseY, z)
        let wantTree: Bool
        if forceTree {
            wantTree = true
        } else {
            switch biome {
            case .swamp: wantTree = Float.random(in: 0...1, using: &rng) < 0.55
            case .forest: wantTree = Float.random(in: 0...1, using: &rng) < 0.72
            case .lava: wantTree = Float.random(in: 0...1, using: &rng) < 0.25
            case .snow: wantTree = Float.random(in: 0...1, using: &rng) < 0.75
            case .tropical: wantTree = Float.random(in: 0...1, using: &rng) < 0.7
            }
        }

        let placed: PlacedObstacle
        var collisionBaseY = baseY
        if wantTree {
            switch biome {
            case .snow:
                placed = ObstacleFactory.makePineTree(at: position, heightScale: 1.5)
            case .tropical:
                placed = ObstacleFactory.makePalmTree(at: position)
            case .swamp:
                let inWater = slowZones.contains(x: x, z: z)
                collisionBaseY = inWater ? baseY + 0.04 : baseY
                placed = ObstacleFactory.makeWillowTree(
                    at: SCNVector3(x, collisionBaseY, z),
                    inWater: inWater
                )
            default:
                placed = ObstacleFactory.makeTree(at: position, scorched: biome == .lava)
            }
        } else {
            let size: CGFloat
            let tint: UIColor?
            switch biome {
            case .snow:
                size = CGFloat.random(in: 0.7...1.3, using: &rng)
                tint = UIColor(red: 0.72, green: 0.78, blue: 0.86, alpha: 1)
            case .tropical:
                size = CGFloat.random(in: 0.7...1.3, using: &rng)
                tint = UIColor(red: 0.72, green: 0.64, blue: 0.42, alpha: 1)
            case .lava:
                // Twice the usual rock scale.
                size = CGFloat.random(in: 1.4...2.6, using: &rng)
                tint = UIColor(red: 0.30, green: 0.17, blue: 0.13, alpha: 1)
            default:
                size = CGFloat.random(in: 0.7...1.3, using: &rng)
                tint = nil
            }
            placed = ObstacleFactory.makeRock(
                at: position,
                sizeRange: size...size,
                color: tint
            )
        }

        container.addChildNode(placed.node)
        obstacles.add(
            ObstacleVolume(
                x: x,
                z: z,
                radius: placed.radius,
                baseY: collisionBaseY,
                height: placed.height,
                chunkEndZ: endZ
            )
        )

        // Solid ground coconuts beside playable-path palms.
        if biome == .tropical, wantTree {
            placeCoconutsNearPalm(
                on: container,
                palmX: x,
                palmZ: z,
                endZ: endZ,
                onDunes: false
            )
        }
    }

    /// Collectible coins along the playable path in every biome.
    private func placeCoins(on container: SCNNode, startZ: Float, endZ: Float) {
        let count = Int.random(in: 2...4, using: &rng)
        var placed = 0
        var attempts = 0
        while placed < count && attempts < 24 {
            attempts += 1
            let x = Float.random(in: (-Self.trackWidth * 0.38)...(Self.trackWidth * 0.38), using: &rng)
            let z = startZ + Float.random(in: 3...(Self.chunkLength - 3), using: &rng)
            if isBlocked(x: x, z: z) || isTooSteep(x: x, z: z) { continue }
            if obstacles.isNear(x: x, z: z, minSeparation: 1.6) { continue }
            let y = heightField.height(atX: x, z: z)
            coins.add(atX: x, z: z, y: y, chunkEndZ: endZ, parent: container)
            placed += 1
        }
    }

    /// Ground coconut piles beside a palm — playable path (solid) or dune shelves (decor).
    private func placeCoconutsNearPalm(
        on container: SCNNode,
        palmX: Float,
        palmZ: Float,
        endZ: Float,
        onDunes: Bool
    ) {
        let halfPath = Self.trackWidth * 0.5
        let maxAbsX = onDunes
            ? halfPath + Self.tropicalSideExtent - 1.5
            : Self.trackWidth * 0.47
        let count = Int.random(in: 2...5, using: &rng)
        for _ in 0..<count {
            let angle = Float.random(in: 0...(Float.pi * 2), using: &rng)
            let dist = Float.random(in: 1.15...2.6, using: &rng)
            let cx = palmX + cos(angle) * dist
            let cz = palmZ + sin(angle) * dist
            if onDunes {
                if abs(cx) < halfPath + 1.0 || abs(cx) > maxAbsX { continue }
            } else {
                if abs(cx) > maxAbsX { continue }
                if isTooSteep(x: cx, z: cz) { continue }
            }
            let baseY = onDunes || abs(cx) > halfPath
                ? Self.tropicalDuneHeight(worldX: cx, worldZ: cz)
                : heightField.height(atX: cx, z: cz)
            let coconut = ObstacleFactory.makeCoconut(at: SCNVector3(cx, baseY, cz))
            container.addChildNode(coconut.node)
            if onDunes {
                coconut.node.name = "edgeDecor"
            } else {
                obstacles.add(
                    ObstacleVolume(
                        x: cx,
                        z: cz,
                        radius: coconut.radius,
                        baseY: baseY,
                        height: coconut.height,
                        chunkEndZ: endZ
                    )
                )
            }
        }
    }

    /// Ground coconut piles beside dune palms (outside the playable path).
    private func placeCoconutsNearDunePalm(
        on container: SCNNode,
        palmX: Float,
        palmZ: Float
    ) {
        placeCoconutsNearPalm(
            on: container,
            palmX: palmX,
            palmZ: palmZ,
            endZ: palmZ,
            onDunes: true
        )
    }

    /// Avoid planting rocks/trees on steep hill faces where they look like they float.
    private func isTooSteep(x: Float, z: Float) -> Bool {
        let sample: Float = 0.7
        let h = heightField.height(atX: x, z: z)
        let hx = heightField.height(atX: x + sample, z: z)
        let hz = heightField.height(atX: x, z: z + sample)
        let gradient = max(abs(hx - h), abs(hz - h)) / sample
        return gradient > 0.75
    }

    private func isBlocked(x: Float, z: Float) -> Bool {
        if raisedZones.contains(where: { z >= $0.start && z <= $0.end }) {
            return true
        }
        if blockedFootprints.contains(where: {
            z >= $0.startZ && z <= $0.endZ && x >= $0.minX && x <= $0.maxX
        }) {
            return true
        }
        // Keep rocks/trees/etc from stacking on top of each other.
        return obstacles.isNear(x: x, z: z)
    }

    private func addEdgeWater(
        to container: SCNNode,
        startZ: Float,
        pathWidth: Float,
        length: Float,
        fromColor: UIColor,
        toColor: UIColor,
        centerX: Float = 0
    ) {
        let waterWidth = Float(Self.waterExtent + 50)
        let halfPath = pathWidth * 0.5
        let waterSurfaceY: Float = -1.25
        let leftX = centerX - halfPath - waterWidth * 0.5
        let rightX = centerX + halfPath + waterWidth * 0.5

        func makeWater(at x: Float) -> SCNNode {
            let node = GameArt.makeWaterStrip(
                width: waterWidth,
                length: length,
                fromColor: fromColor,
                toColor: toColor,
                segments: 20
            )
            node.position = SCNVector3(x, waterSurfaceY, startZ)
            return node
        }

        container.addChildNode(makeWater(at: leftX))
        container.addChildNode(makeWater(at: rightX))
    }

    /// Biome-flavored scenery outside the playable path (decorative — no collision).
    private func addBiomeEdgeScenery(
        to container: SCNNode,
        startZ: Float,
        endZ: Float,
        biome: Biome
    ) {
        switch biome {
        case .lava:
            addLavaVolcanoScenery(to: container, startZ: startZ, endZ: endZ)
        case .tropical:
            addTropicalBeach(to: container, startZ: startZ, endZ: endZ)
        case .forest:
            addSideBanks(to: container, startZ: startZ, biome: .forest, width: 48)
            addSideForestTrees(to: container, startZ: startZ, endZ: endZ)
        case .snow:
            addSideBanks(to: container, startZ: startZ, biome: .snow, width: 52)
            addSideSnowMountains(to: container, startZ: startZ, endZ: endZ)
        case .swamp:
            addSideSwampScenery(to: container, startZ: startZ, endZ: endZ)
        }
    }

    /// Land shelves just outside the path so side props don't float in open water.
    private func addSideBanks(
        to container: SCNNode,
        startZ: Float,
        biome: Biome,
        width bankWidth: Float = 42
    ) {
        let halfPath = Self.trackWidth * 0.5
        let overlap: Float = 0.7
        let material = GameArt.groundMaterial(for: biome)
        let totalWidth = bankWidth + overlap

        func makeBank(centerX: Float) {
            let box = SCNBox(
                width: CGFloat(totalWidth),
                height: 0.45,
                length: CGFloat(Self.chunkLength + 1.2),
                chamferRadius: 0
            )
            box.firstMaterial = material
            let node = SCNNode(geometry: box)
            node.name = "edgeBank"
            node.position = SCNVector3(centerX, -0.02, startZ + Self.chunkLength * 0.5)
            node.castsShadow = false
            container.addChildNode(node)
        }

        makeBank(centerX: -(halfPath + totalWidth * 0.5 - overlap))
        makeBank(centerX: halfPath + totalWidth * 0.5 - overlap)
    }

    private func addSideForestTrees(to container: SCNNode, startZ: Float, endZ: Float) {
        let halfPath = Self.trackWidth * 0.5
        let count = Int.random(in: 16...24, using: &rng)
        for _ in 0..<count {
            let side: Float = Bool.random(using: &rng) ? -1 : 1
            let x = side * Float.random(in: (halfPath + 1.5)...(halfPath + 44), using: &rng)
            let z = Float.random(in: startZ...(endZ - 0.5), using: &rng)
            let tree = ObstacleFactory.makeTree(at: SCNVector3(x, 0.05, z))
            tree.node.name = "edgeDecor"
            // Slightly scale outer trees up so they form a thicker wall.
            let grow = Float.random(in: 1.0...1.35, using: &rng)
            tree.node.scale = SCNVector3(grow, grow, grow)
            container.addChildNode(tree.node)
        }

        // Match the playable forest denseness with side bushes and rocks (decor only).
        for _ in 0..<Int.random(in: 14...22, using: &rng) {
            let side: Float = Bool.random(using: &rng) ? -1 : 1
            let x = side * Float.random(in: (halfPath + 1.2)...(halfPath + 40), using: &rng)
            let z = Float.random(in: startZ...(endZ - 0.5), using: &rng)
            let berries = Float.random(in: 0...1, using: &rng) < 0.45
            let bush = ObstacleFactory.makeBush(
                at: SCNVector3(x, 0.05, z),
                scaleRange: 0.9...1.45,
                withBerries: berries
            )
            bush.name = "edgeDecor"
            container.addChildNode(bush)
        }

        for _ in 0..<Int.random(in: 8...14, using: &rng) {
            let side: Float = Bool.random(using: &rng) ? -1 : 1
            let x = side * Float.random(in: (halfPath + 2)...(halfPath + 36), using: &rng)
            let z = Float.random(in: startZ...(endZ - 0.5), using: &rng)
            let rock = ObstacleFactory.makeRock(
                at: SCNVector3(x, 0.05, z),
                sizeRange: 0.55...1.15
            )
            rock.node.name = "edgeDecor"
            container.addChildNode(rock.node)
        }
    }

    private func addSideSnowMountains(to container: SCNNode, startZ: Float, endZ: Float) {
        let halfPath = Self.trackWidth * 0.5
        let count = Int.random(in: 9...14, using: &rng)
        for _ in 0..<count {
            let side: Float = Bool.random(using: &rng) ? -1 : 1
            let x = side * Float.random(in: (halfPath + 14)...(halfPath + 58), using: &rng)
            let z = Float.random(in: (startZ + 1)...(endZ - 1), using: &rng)
            let peak = CGFloat.random(in: 10...22, using: &rng)
            let mountain = ObstacleFactory.makeSnowMountain(
                at: SCNVector3(x, -0.2, z),
                peakHeight: peak
            )
            container.addChildNode(mountain)
        }

        for _ in 0..<Int.random(in: 8...14, using: &rng) {
            let side: Float = Bool.random(using: &rng) ? -1 : 1
            let x = side * Float.random(in: (halfPath + 2)...(halfPath + 22), using: &rng)
            let z = Float.random(in: startZ...(endZ - 0.5), using: &rng)
            let pine = ObstacleFactory.makePineTree(at: SCNVector3(x, 0.05, z), heightScale: 1.5)
            pine.node.name = "edgeDecor"
            container.addChildNode(pine.node)
        }
    }

    private func addSideSwampScenery(to container: SCNNode, startZ: Float, endZ: Float) {
        let halfPath = Self.trackWidth * 0.5
        // Solid swamp ground so props aren't floating in open water.
        addSideBanks(to: container, startZ: startZ, biome: .swamp, width: 40)

        // Twice the edge water coverage for a wetter swamp fringe.
        for _ in 0..<Int.random(in: 4...8, using: &rng) {
            let side: Float = Bool.random(using: &rng) ? -1 : 1
            let radius = Float.random(in: 2.2...3.8, using: &rng)
            let x = side * Float.random(in: (halfPath + 4)...(halfPath + 28), using: &rng)
            let z = Float.random(in: (startZ + 2)...(endZ - 2), using: &rng)
            let water = SCNCylinder(radius: CGFloat(radius), height: 0.1)
            water.radialSegmentCount = 10
            water.firstMaterial = GameArt.pondMaterial()
            let node = SCNNode(geometry: water)
            node.name = "edgeDecor"
            node.position = SCNVector3(x, 0.04, z)
            node.castsShadow = false
            container.addChildNode(node)
        }

        for _ in 0..<Int.random(in: 6...10, using: &rng) {
            let side: Float = Bool.random(using: &rng) ? -1 : 1
            let x = side * Float.random(in: (halfPath + 2)...(halfPath + 32), using: &rng)
            let z = Float.random(in: startZ...(endZ - 0.5), using: &rng)
            let willow = ObstacleFactory.makeSimpleWillow(
                at: SCNVector3(x, 0.05, z),
                inWater: false
            )
            willow.node.name = "edgeDecor"
            container.addChildNode(willow.node)
        }
    }

    /// Scorched banks + side volcanoes, with free-floating lava pockets on the path.
    private func addLavaVolcanoScenery(to container: SCNNode, startZ: Float, endZ: Float) {
        let halfPath = Self.trackWidth * 0.5
        addSideBanks(to: container, startZ: startZ, biome: .lava, width: 56)

        for side: Float in [-1, 1] {
            let count = Int.random(in: 1...2, using: &rng)
            for _ in 0..<count {
                let x = side * Float.random(in: (halfPath + 10)...(halfPath + 42), using: &rng)
                let z = Float.random(in: (startZ + 2)...(endZ - 2), using: &rng)
                let peak = CGFloat.random(in: 9...18, using: &rng)
                let volcano = ObstacleFactory.makeVolcano(
                    at: SCNVector3(x, -0.15, z),
                    peakHeight: peak,
                    side: side
                )
                container.addChildNode(volcano)
            }
        }
    }

    /// Molten pools on the playfield — edges and toward the middle.
    @discardableResult
    private func addLavaPockets(
        to container: SCNNode,
        startZ: Float,
        endZ: Float
    ) -> [(x: Float, z: Float, radius: Float)] {
        let halfPath = Self.trackWidth * 0.5
        let count = Int.random(in: 3...6, using: &rng)
        var placed: [(x: Float, z: Float, radius: Float)] = []

        for _ in 0..<count {
            let x: Float
            if Float.random(in: 0...1, using: &rng) < 0.5 {
                // Toward the middle of the playable area.
                x = Float.random(in: (-halfPath * 0.55)...(halfPath * 0.55), using: &rng)
            } else {
                let side: Float = Bool.random(using: &rng) ? -1 : 1
                x = side * Float.random(in: (halfPath * 0.55)...(halfPath * 0.92), using: &rng)
            }
            let z = startZ + Float.random(in: 3...(Self.chunkLength - 3), using: &rng)
            let poolRadius = Float.random(in: 1.1...1.9, using: &rng)
            if isBlocked(x: x, z: z) { continue }
            let tooClose = placed.contains {
                hypot(x - $0.x, z - $0.z) < ($0.radius + poolRadius + 1.5)
            }
            if tooClose { continue }

            let landY = heightField.height(atX: x, z: z) + 0.05
            let pool = SCNCylinder(radius: CGFloat(poolRadius), height: 0.1)
            pool.radialSegmentCount = 12
            pool.firstMaterial = GameArt.lavaGlowMaterial(intensity: 1.1)
            let poolNode = SCNNode(geometry: pool)
            poolNode.name = "hazard"
            poolNode.position = SCNVector3(x, landY, z)
            poolNode.castsShadow = false
            // Slight oval so pockets aren't perfect circles.
            poolNode.scale = SCNVector3(
                Float.random(in: 0.85...1.2, using: &rng),
                1,
                Float.random(in: 0.85...1.2, using: &rng)
            )
            container.addChildNode(poolNode)

            slowZones.add(
                SlowZone(
                    minX: x - poolRadius,
                    maxX: x + poolRadius,
                    startZ: z - poolRadius,
                    endZ: z + poolRadius,
                    speedScale: 0.58,
                    chunkEndZ: endZ
                )
            )
            blockedFootprints.append((
                z - poolRadius,
                z + poolRadius,
                x - poolRadius,
                x + poolRadius
            ))
            placed.append((x, z, poolRadius))
        }
        return placed
    }

    /// Palm decor on the beach side shelves (terrain itself is part of the main ground mesh).
    private func addTropicalBeach(to container: SCNNode, startZ: Float, endZ: Float) {
        let halfPath = Self.trackWidth * 0.5
        let outer = halfPath + Self.tropicalSideExtent - 3

        for side: Float in [-1, 1] {
            for _ in 0..<Int.random(in: 2...4, using: &rng) {
                let x = side * Float.random(in: (halfPath + 2.5)...outer, using: &rng)
                let z = Float.random(in: (startZ + 1.5)...(endZ - 1.5), using: &rng)
                let y = Self.tropicalDuneHeight(worldX: x, worldZ: z)
                let palm = ObstacleFactory.makePalmTree(at: SCNVector3(x, y, z))
                palm.node.name = "edgeDecor"
                container.addChildNode(palm.node)
                // Ground husks beside dune palms (outside the playable area).
                placeCoconutsNearDunePalm(on: container, palmX: x, palmZ: z)
            }
        }
    }
}
