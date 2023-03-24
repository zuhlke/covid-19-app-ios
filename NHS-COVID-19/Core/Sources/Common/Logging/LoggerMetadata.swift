//
// Copyright © 2020 NHSX. All rights reserved.
//

import Foundation
import Logging
import CustomDump

extension Logger.Metadata {

    public static func describing(_ value: Any) -> Logger.Metadata {
        ["value": .stringConvertible(DescribedValue(value: value))]
    }
}

public struct DescribedValue: CustomStringConvertible {
    public var value: Any
    public var description: String {
        prettyDump(value)
    }
}

public func prettyDump(
    _ value: Any,
    name: String? = nil,
    indent: Int = 0,
    maxDepth: Int = .max
) -> String {
    var out = ""
    customDump(value, to: &out, name: name, indent: indent, maxDepth: maxDepth)
    return out
}
