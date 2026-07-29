import SceneKit
import UIKit

enum SmoothTerrain {
    /// Continuous chunk ground mesh sampled from the height field — hills/divots read as one surface.
    /// Optional `colorAt` A channel marks rock; when `rockMaterial` is set, high-blend triangles use it.
    static func makeChunkGround(
        width: Float,
        length: Float,
        worldStartZ: Float,
        material: SCNMaterial,
        rockMaterial: SCNMaterial? = nil,
        segmentsZ: Int = 28,
        segmentsX: Int = 16,
        heightAt: @escaping (Float, Float) -> Float,
        colorAt: ((Float, Float, Float) -> SIMD4<Float>)? = nil
    ) -> SCNNode {
        let geometry = makeGeometry(
            width: width,
            length: length,
            segmentsZ: segmentsZ,
            segmentsX: segmentsX,
            includeSkirt: true,
            splitRock: rockMaterial != nil && colorAt != nil,
            heightAt: { localX, t in
                heightAt(localX, worldStartZ + t * length)
            },
            colorAt: colorAt.map { colorFn in
                { localX, t, y in
                    colorFn(localX, worldStartZ + t * length, y)
                }
            }
        )
        if let rockMaterial, colorAt != nil {
            geometry.materials = [material, rockMaterial]
        } else {
            geometry.materials = [material]
        }

        let node = SCNNode(geometry: geometry)
        node.name = "ground"
        node.position = SCNVector3(0, 0, worldStartZ)
        node.castsShadow = false
        return node
    }

    private static func makeGeometry(
        width: Float,
        length: Float,
        segmentsZ: Int,
        segmentsX: Int,
        includeSkirt: Bool,
        splitRock: Bool,
        heightAt: (Float, Float) -> Float,
        colorAt: ((Float, Float, Float) -> SIMD4<Float>)?
    ) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var blends: [Float] = []
        var grassIndices: [Int32] = []
        var rockIndices: [Int32] = []

        let cols = segmentsX + 1

        var heights = [Float](repeating: 0, count: cols * (segmentsZ + 1))
        for iz in 0...segmentsZ {
            let t = Float(iz) / Float(segmentsZ)
            for ix in 0...segmentsX {
                let localX = -width * 0.5 + width * Float(ix) / Float(segmentsX)
                heights[iz * cols + ix] = heightAt(localX, t)
            }
        }

        let skirtDepth: Float = includeSkirt ? 1.35 : 0

        func heightSample(_ ix: Int, _ iz: Int) -> Float {
            heights[iz * cols + ix]
        }

        func normalAt(_ ix: Int, _ iz: Int) -> SCNVector3 {
            let ix0 = max(0, ix - 1)
            let ix1 = min(segmentsX, ix + 1)
            let iz0 = max(0, iz - 1)
            let iz1 = min(segmentsZ, iz + 1)
            let dx = width / Float(segmentsX) * Float(max(1, ix1 - ix0))
            let dz = length / Float(segmentsZ) * Float(max(1, iz1 - iz0))
            let dhx = heightSample(ix1, iz) - heightSample(ix0, iz)
            let dhz = heightSample(ix, iz1) - heightSample(ix, iz0)
            let n = SCNVector3(-dhx * dz, dx * dz, -dx * dhz)
            return normalize(n)
        }

        // Top surface — V runs 0...1 along the chunk so biome blends map correctly.
        for iz in 0...segmentsZ {
            let t = Float(iz) / Float(segmentsZ)
            let z = length * t
            for ix in 0...segmentsX {
                let x = -width * 0.5 + width * Float(ix) / Float(segmentsX)
                let y = heightSample(ix, iz)
                vertices.append(SCNVector3(x, y, z))
                normals.append(normalAt(ix, iz))
                uvs.append(CGPoint(x: CGFloat((x + width * 0.5) / 4), y: CGFloat(t)))
                if let colorAt {
                    blends.append(colorAt(x, t, y).w)
                } else {
                    blends.append(0)
                }
            }
        }

        func appendTri(_ a: Int32, _ b: Int32, _ c: Int32) {
            if splitRock {
                let avg = (blends[Int(a)] + blends[Int(b)] + blends[Int(c)]) / 3
                if avg >= 0.28 {
                    rockIndices.append(contentsOf: [a, b, c])
                    return
                }
            }
            grassIndices.append(contentsOf: [a, b, c])
        }

        for iz in 0..<segmentsZ {
            for ix in 0..<segmentsX {
                let i = Int32(iz * cols + ix)
                let next = i + Int32(cols)
                appendTri(i, next, i + 1)
                appendTri(i + 1, next, next + 1)
            }
        }

        if includeSkirt {
            // Side skirts so the chunk edge meets the water without a floating slab look.
            func addSkirt(edgeIndices: [Int], outward: SCNVector3) {
                let base = Int32(vertices.count)
                for (n, topIndex) in edgeIndices.enumerated() {
                    let top = vertices[topIndex]
                    vertices.append(top)
                    normals.append(outward)
                    uvs.append(uvs[topIndex])
                    blends.append(0)
                    vertices.append(SCNVector3(top.x, top.y - skirtDepth, top.z))
                    normals.append(outward)
                    uvs.append(CGPoint(x: uvs[topIndex].x, y: uvs[topIndex].y + 0.3))
                    blends.append(0)
                    if n < edgeIndices.count - 1 {
                        let i = base + Int32(n * 2)
                        // Skirts stay on the grass/ground material.
                        grassIndices.append(contentsOf: [i, i + 1, i + 2, i + 2, i + 1, i + 3])
                    }
                }
            }

            let leftEdge = (0...segmentsZ).map { $0 * cols }
            let rightEdge = (0...segmentsZ).map { $0 * cols + segmentsX }
            let frontEdge = Array(0...segmentsX)
            let backEdge = (0...segmentsX).map { segmentsZ * cols + $0 }

            addSkirt(edgeIndices: leftEdge, outward: SCNVector3(-1, 0, 0))
            addSkirt(edgeIndices: rightEdge, outward: SCNVector3(1, 0, 0))
            addSkirt(edgeIndices: frontEdge, outward: SCNVector3(0, 0, -1))
            addSkirt(edgeIndices: backEdge, outward: SCNVector3(0, 0, 1))
        }

        let src = SCNGeometrySource(vertices: vertices)
        let nrm = SCNGeometrySource(normals: normals)
        let uv = SCNGeometrySource(textureCoordinates: uvs)

        var elements: [SCNGeometryElement] = [
            SCNGeometryElement(indices: grassIndices, primitiveType: .triangles)
        ]
        if splitRock {
            // Always include a rock element so material index 1 is valid even if empty.
            let rock = rockIndices.isEmpty ? [Int32(0), Int32(0), Int32(0)] : rockIndices
            elements.append(SCNGeometryElement(indices: rock, primitiveType: .triangles))
        }

        return SCNGeometry(sources: [src, nrm, uv], elements: elements)
    }

    private static func normalize(_ v: SCNVector3) -> SCNVector3 {
        let len = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
        guard len > 0.00001 else { return SCNVector3(0, 1, 0) }
        return SCNVector3(v.x / len, v.y / len, v.z / len)
    }
}
