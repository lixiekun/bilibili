import SwiftUI
import RealityKit
import AVKit
import UIKit

/// 官方 Demo 风格的演播室沉浸场景，用来与影院模式做对比。
struct StudioView: View {
    @StateObject private var playerModel = PlayerModel.shared
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    
    @State private var scale: CGFloat = 1.05
    @State private var distance: CGFloat = -5.5
    @State private var isControlsVisible: Bool = true
    @State private var isDanmakuVisible: Bool = true
    @State private var controlsOffset: CGPoint = .zero
    @State private var lightingStyle: StudioLightingStyle = .dark
    
    var body: some View {
        RealityView { content, attachments in
            let root = Entity()
            root.name = "StudioRoot"
            root.position = [0, 1.4, Float(distance)]
            content.add(root)
            
            addEnvironment(to: root)
            addScreen(to: root)
            
            if let controls = attachments.entity(for: "controls") {
                controls.position = [0, 1.0, -0.7]
                controls.name = "StudioControls"
                controls.isEnabled = isControlsVisible
                content.add(controls)
            }
            
            if let danmaku = attachments.entity(for: "danmaku"),
               let screen = root.findEntity(named: "StudioScreen") {
                danmaku.position = [0, 0, 0.01]
                danmaku.name = "DanmakuLayer"
                screen.addChild(danmaku)
            }
        } update: { content, _ in
            guard let root = content.entities.first(where: { $0.name == "StudioRoot" }) else { return }
            root.position.z = Float(distance)
            
            updateEnvironment(root: root)
            updateScreen(in: root)
            updateControls(in: content)
        } attachments: {
            Attachment(id: "controls") {
                CinemaControlsView(
                    player: playerModel.player,
                    distance: $distance,
                    scale: $scale,
                    isDanmakuVisible: $isDanmakuVisible,
                    dragOffset: $controlsOffset,
                    onExit: exitImmersive
                )
                .frame(width: 560)
            }
            
            Attachment(id: "danmaku") {
                DanmakuView(engine: playerModel.danmakuEngine, player: playerModel.player)
                    .frame(width: 1920, height: 1080)
                    .allowsHitTesting(false)
            }
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    if value.entity.name == "StudioScreen" || value.entity.name == "StudioRoot" {
                        withAnimation(.easeInOut) {
                            isControlsVisible.toggle()
                        }
                    }
                }
        )
        .ornament(attachmentAnchor: OrnamentAttachmentAnchor.scene(.topLeading)) {
            Picker("灯光", selection: $lightingStyle) {
                ForEach(StudioLightingStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassBackgroundEffect()
        }
        .onAppear {
            print("🎬 StudioView onAppear")
            playerModel.isImmersiveMode = true
        }
    }
    
    private func addEnvironment(to root: Entity) {
        let domeMesh = MeshResource.generateSphere(radius: 12)
        let dome = ModelEntity(
            mesh: domeMesh,
            materials: [simpleMaterial(color: lightingStyle.domeColor, metallic: false, roughness: 0)]
        )
        dome.name = "StudioDome"
        dome.scale = [-1, 1, 1] // 反转法线以便从内部看到贴图
        root.addChild(dome)
        
        let floorMesh = MeshResource.generatePlane(width: 12, height: 12)
        let floor = ModelEntity(mesh: floorMesh, materials: [simpleMaterial(color: lightingStyle.floorColor, metallic: true, roughness: 0.18)])
        floor.name = "StudioFloor"
        floor.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        floor.position = [0, -0.3, 0]
        root.addChild(floor)
        
        let stage = ModelEntity(
            mesh: MeshResource.generateBox(size: [8, 0.14, 3.2], cornerRadius: 0.2),
            materials: [simpleMaterial(color: lightingStyle.stageColor, metallic: true, roughness: 0.25)]
        )
        stage.name = "StudioStage"
        stage.position = [0, 0.55, -0.2]
        root.addChild(stage)
        
        let ringMesh = MeshResource.generateCylinder(height: 0.05, radius: 3.0)
        let ring = ModelEntity(mesh: ringMesh, materials: [simpleMaterial(color: lightingStyle.accentColor, metallic: true, roughness: 0.05)])
        ring.name = "StudioRing"
        ring.position = [0, 1.4, -0.25]
        ring.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        root.addChild(ring)
        
        let keyLight = DirectionalLight()
        keyLight.name = "StudioKeyLight"
        keyLight.light.intensity = lightingStyle.keyLightIntensity
        keyLight.light.color = lightingStyle.keyLightColor
        keyLight.look(at: [0, 1.2, 0], from: [3.0, 3.4, 2.0], relativeTo: nil)
        root.addChild(keyLight)
        
        let fillLight = DirectionalLight()
        fillLight.name = "StudioFillLight"
        fillLight.light.intensity = lightingStyle.fillLightIntensity
        fillLight.light.color = lightingStyle.fillLightColor
        fillLight.look(at: [0, 1.2, 0], from: [-2.2, 2.8, 2.8], relativeTo: nil)
        root.addChild(fillLight)
    }
    
    private func addScreen(to root: Entity) {
        let backdrop = ModelEntity(
            mesh: MeshResource.generatePlane(width: 8.4, height: 4.8, cornerRadius: 0.42),
            materials: [simpleMaterial(color: lightingStyle.backdropColor, metallic: true, roughness: 0.12)]
        )
        backdrop.name = "StudioBackdrop"
        backdrop.position = [0, 1.4, -0.08]
        root.addChild(backdrop)
        
        let screen = ModelEntity(mesh: MeshResource.generatePlane(width: 7.6, height: 4.275, cornerRadius: 0.22))
        screen.name = "StudioScreen"
        screen.position = [0, 1.4, 0]
        screen.generateCollisionShapes(recursive: false)
        screen.components.set(InputTargetComponent())
        
        if let player = playerModel.player {
            screen.model?.materials = [VideoMaterial(avPlayer: player)]
        } else {
            screen.model?.materials = [SimpleMaterial(color: .black, isMetallic: false)]
        }
        
        root.addChild(screen)
        
        let frame = ModelEntity(
            mesh: MeshResource.generatePlane(width: 8.0, height: 4.7, cornerRadius: 0.3),
            materials: [simpleMaterial(color: lightingStyle.stageColor.withAlphaComponent(0.45), metallic: true, roughness: 0.18)]
        )
        frame.name = "StudioFrame"
        frame.position = [0, 1.4, -0.04]
        root.addChild(frame)
    }
    
    private func updateEnvironment(root: Entity) {
        if let dome = root.findEntity(named: "StudioDome") as? ModelEntity {
            dome.model?.materials = [simpleMaterial(color: lightingStyle.domeColor, metallic: false, roughness: 0)]
        }
        if let floor = root.findEntity(named: "StudioFloor") as? ModelEntity {
            floor.model?.materials = [simpleMaterial(color: lightingStyle.floorColor, metallic: true, roughness: 0.18)]
        }
        if let stage = root.findEntity(named: "StudioStage") as? ModelEntity {
            stage.model?.materials = [simpleMaterial(color: lightingStyle.stageColor, metallic: true, roughness: 0.25)]
        }
        if let ring = root.findEntity(named: "StudioRing") as? ModelEntity {
            ring.model?.materials = [simpleMaterial(color: lightingStyle.accentColor, metallic: true, roughness: 0.05)]
        }
        if let frame = root.findEntity(named: "StudioFrame") as? ModelEntity {
            frame.model?.materials = [simpleMaterial(color: lightingStyle.stageColor.withAlphaComponent(0.45), metallic: true, roughness: 0.18)]
        }
        if let backdrop = root.findEntity(named: "StudioBackdrop") as? ModelEntity {
            backdrop.model?.materials = [simpleMaterial(color: lightingStyle.backdropColor, metallic: true, roughness: 0.12)]
        }
        if let keyLight = root.findEntity(named: "StudioKeyLight") as? DirectionalLight {
            keyLight.light.intensity = lightingStyle.keyLightIntensity
            keyLight.light.color = lightingStyle.keyLightColor
        }
        if let fillLight = root.findEntity(named: "StudioFillLight") as? DirectionalLight {
            fillLight.light.intensity = lightingStyle.fillLightIntensity
            fillLight.light.color = lightingStyle.fillLightColor
        }
    }
    
    private func updateScreen(in root: Entity) {
        guard let screen = root.findEntity(named: "StudioScreen") as? ModelEntity else { return }
        
        // 缩放屏幕
        screen.scale = [Float(scale), Float(scale), Float(scale)]
        
        // 视频材质保持最新的 AVPlayer
        if let player = playerModel.player {
            screen.model?.materials = [VideoMaterial(avPlayer: player)]
        } else {
            screen.model?.materials = [SimpleMaterial(color: .black, isMetallic: false)]
        }
        
        // 更新弹幕层
        if let danmaku = screen.findEntity(named: "DanmakuLayer") {
            danmaku.isEnabled = isDanmakuVisible
            let bounds = danmaku.visualBounds(relativeTo: danmaku)
            let localWidth = bounds.extents.x
            if localWidth > 0 {
                let targetWidth: Float = 7.2
                let s = targetWidth / localWidth
                if abs(danmaku.scale.x - s) > 0.001 {
                    danmaku.scale = [s, s, s]
                }
            }
        }
    }
    
    private func updateControls(in content: RealityViewContent) {
        if let controls = content.entities.first(where: { $0.name == "StudioControls" }) {
            controls.isEnabled = isControlsVisible
            let x = Float(controlsOffset.x) / 1000.0
            let y = Float(-controlsOffset.y) / 1000.0
            controls.position = [x, 1.0 + y, -0.7]
        }
    }
    
    private func exitImmersive() {
        Task {
            await dismissImmersiveSpace()
            playerModel.isImmersiveMode = false
            
            if playerModel.restoringVideoItem == nil {
                playerModel.restoringVideoItem = playerModel.currentVideoItem
            }
            
            playerModel.cleanup()
            openWindow(id: "MainWindow")
            dismissWindow(id: "PlayerWindow")
        }
    }
    
    private func simpleMaterial(color: UIColor, metallic: Bool = false, roughness: Float = 0.3) -> SimpleMaterial {
        SimpleMaterial(
            color: color,
            roughness: .init(floatLiteral: roughness),
            isMetallic: metallic
        )
    }
}

private enum StudioLightingStyle: String, CaseIterable, Identifiable {
    case dark
    case warm
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .dark:
            return "冷色演播室"
        case .warm:
            return "暖光演播室"
        }
    }
    
    var domeColor: UIColor {
        switch self {
        case .dark:
            return UIColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1.0)
        case .warm:
            return UIColor(red: 0.12, green: 0.07, blue: 0.05, alpha: 1.0)
        }
    }
    
    var backdropColor: UIColor {
        switch self {
        case .dark:
            return UIColor(red: 0.12, green: 0.18, blue: 0.3, alpha: 0.9)
        case .warm:
            return UIColor(red: 0.45, green: 0.25, blue: 0.15, alpha: 0.9)
        }
    }
    
    var accentColor: UIColor {
        switch self {
        case .dark:
            return UIColor(red: 0.18, green: 0.55, blue: 0.95, alpha: 1.0)
        case .warm:
            return UIColor(red: 0.95, green: 0.56, blue: 0.3, alpha: 1.0)
        }
    }
    
    var floorColor: UIColor {
        switch self {
        case .dark:
            return UIColor(red: 0.08, green: 0.1, blue: 0.13, alpha: 1.0)
        case .warm:
            return UIColor(red: 0.14, green: 0.11, blue: 0.08, alpha: 1.0)
        }
    }
    
    var stageColor: UIColor {
        switch self {
        case .dark:
            return UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1.0)
        case .warm:
            return UIColor(red: 0.22, green: 0.16, blue: 0.12, alpha: 1.0)
        }
    }
    
    var keyLightIntensity: Float {
        switch self {
        case .dark:
            return 1400
        case .warm:
            return 1700
        }
    }
    
    var fillLightIntensity: Float {
        switch self {
        case .dark:
            return 700
        case .warm:
            return 900
        }
    }
    
    var keyLightColor: UIColor {
        switch self {
        case .dark:
            return UIColor(red: 0.7, green: 0.85, blue: 1.0, alpha: 1.0)
        case .warm:
            return UIColor(red: 1.0, green: 0.88, blue: 0.72, alpha: 1.0)
        }
    }
    
    var fillLightColor: UIColor {
        switch self {
        case .dark:
            return UIColor(red: 0.4, green: 0.55, blue: 0.85, alpha: 1.0)
        case .warm:
            return UIColor(red: 0.93, green: 0.73, blue: 0.52, alpha: 1.0)
        }
    }
    
    var brightness: ImmersiveContentBrightness {
        switch self {
        case .dark:
            return .dark
        case .warm:
            return .dim
        }
    }
    
    var surroundingsEffect: SurroundingsEffect? {
        switch self {
        case .dark:
            return .colorMultiply(Color(red: 0.08, green: 0.12, blue: 0.2))
        case .warm:
            return .colorMultiply(Color(red: 1.0, green: 0.93, blue: 0.82))
        }
    }
}
