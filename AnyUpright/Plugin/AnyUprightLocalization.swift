//
//  AnyUprightLocalization.swift
//  AnyUpright
//

import Foundation

enum AUStringKey: String, CaseIterable {
    case horizonDescription = "AnyUpright::Horizon Description"
    case innerStretchDescription = "AnyUpright::Inner Stretch Description"
    case outerStretchDescription = "AnyUpright::Outer Stretch Description"
    case innerStretchOSCDescription = "AnyUpright::Inner Stretch OSC Description"
    case outerStretchOSCDescription = "AnyUpright::Outer Stretch OSC Description"
    case uprightDescription = "AnyUpright::Upright Description"
    case uprightOSCDescription = "AnyUpright::Upright OSC Description"

    case analyzeHorizon = "AnyUpright::Parameter Analyze Horizon"
    case analyze = "AnyUpright::Parameter Analyze"
    case rotation = "AnyUpright::Parameter Rotation"
    case fillFrame = "AnyUpright::Parameter Fill Frame"
    case ratio = "AnyUpright::Parameter Ratio"
    case editMode = "AnyUpright::Parameter Edit Mode"
    case setUnsetKeyFrame = "AnyUpright::Parameter Set Unset Key Frame"
    case defaults = "AnyUpright::Parameter Defaults"
    case direction = "AnyUpright::Parameter Direction"
    case mode = "AnyUpright::Parameter Mode"
    case autoCrop = "AnyUpright::Parameter Auto Crop"
    case analysisStatus = "AnyUpright::Parameter Analysis Status"
    case verticalPerspective = "AnyUpright::Parameter Vertical Perspective"
    case horizontalPerspective = "AnyUpright::Parameter Horizontal Perspective"

    case none = "AnyUpright::Menu None"
    case fit = "AnyUpright::Menu Fit"
    case fill = "AnyUpright::Menu Fill"
    case vertical = "AnyUpright::Menu Vertical"
    case horizontal = "AnyUpright::Menu Horizontal"
    case full = "AnyUpright::Menu Full"
    case manual = "AnyUpright::Menu Manual"
    case semiAuto = "AnyUpright::Menu Semi Auto"
    case automatic = "AnyUpright::Menu Auto"
    case outerStretch = "AnyUpright::Menu Outer Stretch"
    case innerStretch = "AnyUpright::Menu Inner Stretch"

    case topLeft = "AnyUpright::Corner Top Left"
    case topRight = "AnyUpright::Corner Top Right"
    case bottomRight = "AnyUpright::Corner Bottom Right"
    case bottomLeft = "AnyUpright::Corner Bottom Left"
    case topLeftX = "AnyUpright::Corner Top Left X px"
    case topLeftY = "AnyUpright::Corner Top Left Y px"
    case topRightX = "AnyUpright::Corner Top Right X px"
    case topRightY = "AnyUpright::Corner Top Right Y px"
    case bottomRightX = "AnyUpright::Corner Bottom Right X px"
    case bottomRightY = "AnyUpright::Corner Bottom Right Y px"
    case bottomLeftX = "AnyUpright::Corner Bottom Left X px"
    case bottomLeftY = "AnyUpright::Corner Bottom Left Y px"

    case guides = "AnyUpright::Guides"
    case guideNumber = "AnyUpright::Guide Number"
    case guideEnabled = "AnyUpright::Guide Enabled"
    case guideOrientation = "AnyUpright::Guide Orientation"
    case guideStart = "AnyUpright::Guide Start"
    case guideEnd = "AnyUpright::Guide End"
    case detectedCandidates = "AnyUpright::Detected Candidates"
    case candidateNumber = "AnyUpright::Candidate Number"
    case candidateVisible = "AnyUpright::Candidate Visible"
    case candidateSelected = "AnyUpright::Candidate Selected"
    case candidateOrientation = "AnyUpright::Candidate Orientation"
    case candidateStart = "AnyUpright::Candidate Start"
    case candidateEnd = "AnyUpright::Candidate End"
    case candidateScore = "AnyUpright::Candidate Score"

    case modelLoading = "AnyUpright::Analysis Model Loading"
    case analyzingFrame = "AnyUpright::Analysis Frame Analyzing"
    case keyframesSet = "AnyUpright::Keyframes Set"
    case keyframesRemoved = "AnyUpright::Keyframes Removed"
    case horizonAnalysisError = "AnyUpright::Horizon Analysis Error"
    case uprightAnalysisError = "AnyUpright::Upright Analysis Error"

    case defaultsNewInstancesOnly = "AnyUpright::Defaults New Instances Only"
    case defaultsRestoreFactory = "AnyUpright::Defaults Restore Factory"
    case defaultsSaveFailed = "AnyUpright::Defaults Save Failed"
    case horizonDefaultsTitle = "AnyUpright::Horizon Defaults Title"
    case innerStretchDefaultsTitle = "AnyUpright::Inner Stretch Defaults Title"
    case outerStretchDefaultsTitle = "AnyUpright::Outer Stretch Defaults Title"
    case uprightDefaultsTitle = "AnyUpright::Upright Defaults Title"
    case suppressKeyframeNotifications = "AnyUpright::Defaults Suppress Keyframe Notifications"

    var englishFallback: String {
        switch self {
        case .horizonDescription: return "Automatic horizon correction with manual rotation and optional fill."
        case .innerStretchDescription: return "Select an input selection and stretch it to the full frame."
        case .outerStretchDescription: return "Drag the outer output corners for manual perspective warping."
        case .innerStretchOSCDescription: return "Onscreen input selection controls for AnyUpright Inner Stretch."
        case .outerStretchOSCDescription: return "Onscreen outer corner controls for AnyUpright Outer Stretch."
        case .uprightDescription: return "Lightroom-style manual, guided, automatic, and semi-automatic upright correction."
        case .uprightOSCDescription: return "Onscreen guide and candidate line controls for AnyUpright Upright."
        case .analyzeHorizon: return "Analyze Horizon"
        case .analyze: return "Analyze"
        case .rotation: return "Rotation"
        case .fillFrame: return "Fill Frame"
        case .ratio: return "Ratio"
        case .editMode: return "Edit Mode"
        case .setUnsetKeyFrame: return "Set/Unset Key Frame"
        case .defaults: return "Defaults..."
        case .direction: return "Direction"
        case .mode: return "Mode"
        case .autoCrop: return "Auto Crop"
        case .analysisStatus: return "Analysis Status"
        case .verticalPerspective: return "Vertical Perspective"
        case .horizontalPerspective: return "Horizontal Perspective"
        case .none: return "None"
        case .fit: return "Fit"
        case .fill: return "Fill"
        case .vertical: return "Vertical"
        case .horizontal: return "Horizontal"
        case .full: return "Full"
        case .manual: return "Manual"
        case .semiAuto: return "Semi Auto"
        case .automatic: return "Auto"
        case .outerStretch: return "Outer Stretch"
        case .innerStretch: return "Inner Stretch"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomRight: return "Bottom Right"
        case .bottomLeft: return "Bottom Left"
        case .topLeftX: return "Top Left X px"
        case .topLeftY: return "Top Left Y px"
        case .topRightX: return "Top Right X px"
        case .topRightY: return "Top Right Y px"
        case .bottomRightX: return "Bottom Right X px"
        case .bottomRightY: return "Bottom Right Y px"
        case .bottomLeftX: return "Bottom Left X px"
        case .bottomLeftY: return "Bottom Left Y px"
        case .guides: return "Guides"
        case .guideNumber: return "Guide %d"
        case .guideEnabled: return "Guide %d Enabled"
        case .guideOrientation: return "Guide %d Orientation"
        case .guideStart: return "Guide %d Start"
        case .guideEnd: return "Guide %d End"
        case .detectedCandidates: return "Detected Candidates"
        case .candidateNumber: return "Candidate %d"
        case .candidateVisible: return "Candidate %d Visible"
        case .candidateSelected: return "Candidate %d Selected"
        case .candidateOrientation: return "Candidate %d Orientation"
        case .candidateStart: return "Candidate %d Start"
        case .candidateEnd: return "Candidate %d End"
        case .candidateScore: return "Candidate %d Score"
        case .modelLoading: return "Loading model"
        case .analyzingFrame: return "Analyzing frame"
        case .keyframesSet: return "Keyframes set"
        case .keyframesRemoved:
            return "Keyframes removed\nIf the clip already has keyframes, dragging creates a keyframe at the current frame. You do not need to click this button again."
        case .horizonAnalysisError: return "Horizon analysis: %@"
        case .uprightAnalysisError: return "Upright analysis: %@"
        case .defaultsNewInstancesOnly: return "Default parameter values apply only to new filter instances."
        case .defaultsRestoreFactory: return "Restore Factory Defaults"
        case .defaultsSaveFailed: return "Unable to save defaults."
        case .horizonDefaultsTitle: return "Horizon Defaults"
        case .innerStretchDefaultsTitle: return "Inner Stretch Defaults"
        case .outerStretchDefaultsTitle: return "Outer Stretch Defaults"
        case .uprightDefaultsTitle: return "Upright Defaults"
        case .suppressKeyframeNotifications: return "Don't show keyframe notifications"
        }
    }
}

struct AULocalizer {
    let bundle: Bundle

    func text(_ key: AUStringKey) -> String {
        bundle.localizedString(
            forKey: key.rawValue,
            value: key.englishFallback,
            table: nil
        )
    }

    func format(_ key: AUStringKey, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}

private final class AUPluginLocalizationBundleToken {}

enum AUL10n {
    static let plugin = AULocalizer(bundle: Bundle(for: AUPluginLocalizationBundleToken.self))
}
