public enum ChargeControlMenuVisibility {
    public static func isCoreControlHidden(showsAdvancedControls: Bool) -> Bool {
        false
    }

    public static func isAdvancedControlHidden(showsAdvancedControls: Bool) -> Bool {
        !showsAdvancedControls
    }

    public static func shouldStartDaemonOnApplicationLaunch() -> Bool {
        false
    }

    public static func shouldStartDaemonWhenShowingAdvancedControls(
        showsAdvancedControls: Bool
    ) -> Bool {
        false
    }
}
