//
//  Optional.swift
//  Saga
//
//  Created by Dylan Gattey on 7/12/25.
//

infix operator ??=: AssignmentPrecedence

extension Optional {
    
    /// Assigns only if the lhs is undefined
    static func ??= (lhs: inout Wrapped?, rhs: Wrapped?) {
        if lhs == nil { lhs = rhs }
    }
}
