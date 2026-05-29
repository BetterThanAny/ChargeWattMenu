import Testing
@testable import ChargeWattCore

@Suite
struct ChargeControlMenuVisibilityTests {
    @Test func keepsRangeSettingsVisibleWhenAdvancedControlsAreHidden() {
        #expect(
            ChargeControlMenuVisibility.isCoreControlHidden(
                showsAdvancedControls: false
            ) == false
        )
    }

    @Test func hidesAdvancedActionsWhenAdvancedControlsAreHidden() {
        #expect(
            ChargeControlMenuVisibility.isAdvancedControlHidden(
                showsAdvancedControls: false
            ) == true
        )
    }

    @Test func showsAdvancedActionsWhenAdvancedControlsAreEnabled() {
        #expect(
            ChargeControlMenuVisibility.isAdvancedControlHidden(
                showsAdvancedControls: true
            ) == false
        )
    }

    @Test func doesNotStartDaemonOnApplicationLaunch() {
        #expect(
            ChargeControlMenuVisibility.shouldStartDaemonOnApplicationLaunch() == false
        )
    }

    @Test func startsDaemonWhenAdvancedControlsAreShown() {
        #expect(
            ChargeControlMenuVisibility.shouldStartDaemonWhenShowingAdvancedControls(
                showsAdvancedControls: true
            ) == true
        )
    }

    @Test func doesNotStartDaemonWhenAdvancedControlsAreHidden() {
        #expect(
            ChargeControlMenuVisibility.shouldStartDaemonWhenShowingAdvancedControls(
                showsAdvancedControls: false
            ) == false
        )
    }

    @Test func refreshesDaemonStatusOnlyWhenAdvancedControlsAreShown() {
        #expect(
            ChargeControlMenuVisibility.shouldRefreshDaemonStatusWhenMenuOpens(
                showsAdvancedControls: true
            ) == true
        )
        #expect(
            ChargeControlMenuVisibility.shouldRefreshDaemonStatusWhenMenuOpens(
                showsAdvancedControls: false
            ) == false
        )
    }
}
