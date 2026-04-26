import Foundation

/// Single source of truth for which scenes exist. Add new scenes here and
/// they appear automatically in the picker, configure sheet, and rotator.
enum SceneRegistry {
    static let allScenes: [DemoScene.Type] = [
        PlasmaScene.self,
        SnakeScene.self,
        MatrixScene.self,
        StarfieldScene.self,
        FireScene.self,
        GameOfLifeScene.self,
        DVDScene.self,
        MetaballsScene.self,
        BlizzardScene.self,
        BubblesScene.self,
        ShadebobsScene.self,
        LissajousScene.self,
        MoireScene.self,
        ScintillatingGridScene.self,
        DNAHelixScene.self,
        SpiralPlasmaScene.self,
        DiamondPlasmaScene.self,
        RipplePlasmaScene.self,
        AppleEventScene.self,
        SimultaneousContrastScene.self,
        AfterimageScene.self,
        TunnelScene.self,
        RotozoomerScene.self,
        Mode7Scene.self,
        VectorBallsScene.self,
        HypercubeScene.self,
        CopperBarsScene.self,
        RasterBarsScene.self,
        SineScrollerScene.self,
        GlenzVectorsScene.self,
        C64DemosceneScene.self,
        FishSchoolingScene.self,
        BugSwarmScene.self,
        LavaLampScene.self,
        MandelbrotScene.self,
        MazeScene.self,
        FallingBlocksScene.self,
        SearchLightScene.self,
        LensFlareScene.self,
        FlagWaveScene.self,
        ParallaxScrollerScene.self,
        RubiksCubeScene.self,
        TruchetTilesScene.self,
        ReactionDiffusionScene.self,
        VoronoiScene.self,
        DLASnowflakeScene.self,
        SlimeMoldScene.self,
        VectorFieldScene.self,
        FallingSandScene.self,
        LSystemTreeScene.self,
        SynthwaveGridScene.self,
        AuroraBorealisScene.self,
        KnotWeaveScene.self,
        PongAIScene.self,
        TronCyclesScene.self,
        ConstellationMakerScene.self,
        RippleTankScene.self,
        Pipes3DScene.self,
    ]

    /// Identifier used by the "pick one at random" mode.
    static let randomIdentifier = "random"

    /// Sentinel used as the default if a saved selection no longer matches a
    /// registered scene (e.g., user upgraded and a scene was removed).
    static let defaultSelection = randomIdentifier

    static func scene(for identifier: String) -> DemoScene.Type? {
        return allScenes.first { $0.identifier == identifier }
    }

    /// Items to populate the picker: ("random", "🎲 Random") + each scene.
    static var pickerItems: [(identifier: String, label: String)] {
        var items: [(String, String)] = [(randomIdentifier, "🎲 Random (rotate every 90s)")]
        items.append(contentsOf: allScenes.map { ($0.identifier, $0.displayName) })
        return items
    }
}
