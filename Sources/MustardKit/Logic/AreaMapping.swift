import Foundation

/// Canonical resolver from a source/recommendation `project` to its area name.
///
/// `project` appears in three forms across the app — the KB folder name the config
/// actually stores (`"DL-Knowledge-Base"`), the short code the maps are keyed by
/// (`"DL"`), and the area name itself (`"Digital Licence"`). This reconciles them so
/// routing (bridge export, board area-stamping) works regardless of which form is held.
public enum AreaMapping {
    /// Area name for a project, or nil if unknown. Accepts the folder-name form
    /// (`"DL-Knowledge-Base"`) and the code form (`"DL"`); `MeetingTaskSync.defaultAreaMap`
    /// is the single source of truth for code → area.
    public static func areaName(forProject project: String) -> String? {
        let map = MeetingTaskSync.defaultAreaMap
        if let area = map[project] { return area }                       // code or area-keyed
        let code = project.replacingOccurrences(of: "-Knowledge-Base", with: "")
        return map[code]                                                  // folder-name form
    }
}
