//
// Copyright (C) 2022 - 2025 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import ServiceManagement

@BTBackgroundActor
public enum BTAppXPCClient {
    private static var retainedAuthorizations: [Data: SimpleAuthRef] = [:]

    public static func getAuthorization() async throws -> Data {
        try await self.getAuthorizationData(rightName: nil)
    }

    public static func getDaemonAuthorization() async throws -> Data {
        try await self.getAuthorizationData(rightName: kSMRightModifySystemDaemons)
    }

    public static func getManageAuthorization() async throws -> Data {
#if DEBUG
        try await self.getAuthorizationData(rightName: nil)
#else
        try await self.getAuthorizationData(rightName: BTAuthorizationRights.manage)
#endif
    }

    private static func getAuthorizationData(rightName: String?) async throws -> Data {
        guard let simpleAuth = SimpleAuth.empty() else {
            throw BTError.notAuthorized
        }

        if let rightName {
            let success = SimpleAuth.acquireInteractive(
                simpleAuth: simpleAuth,
                rightName: rightName
            )
            guard success else {
                throw BTError.notAuthorized
            }
        }

        guard let data = SimpleAuth.toData(simpleAuth: simpleAuth) else {
            throw BTError.malformedData
        }

        self.retainAuthorization(simpleAuth, data: data)
        return data
    }

    private static func retainAuthorization(
        _ simpleAuth: SimpleAuthRef,
        data: Data
    ) {
        self.retainedAuthorizations[data] = simpleAuth
        Task { @BTBackgroundActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            self.retainedAuthorizations[data] = nil
        }
    }
}
