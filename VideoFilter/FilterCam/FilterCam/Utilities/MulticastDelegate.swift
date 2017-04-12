//
//  MulticastDelegate.swift
//  FilterCam
//
//  Created by Shreesha on 03/03/17.
//  Copyright © 2017 YML. All rights reserved.
//

import Foundation
//
//  MulticastDelegate.swift
//  Sequoia
//
//  Created by Karthik Mitta on 22/11/16.
//  Copyright © 2016 YMediaLabs. All rights reserved.
//

import Foundation

open class MulticastDelegate<T> {
    fileprivate (set) var delegates = NSHashTable<AnyObject>.weakObjects()

    //previously
    //fileprivate var delegates = NSHashTable.weakObjects()

    public init() {}

    //previously
    //open func addDelegate(_ delegate: T) {
    //open func removeDelegate(_ delegate: T) {
    open func addDelegate(_ delegate: T?) {
        guard let delegate = delegate else { return }
        delegates.add(delegate as AnyObject?)
    }

    open func removeDelegate(_ delegate: T?) {
        guard let delegate = delegate else { return }
        delegates.remove(delegate as AnyObject?)
    }

    open func invokeDelegates(_ invocation: (T) -> ()) {
        for delegate in delegates.allObjects {
            invocation(delegate as! T)
        }
    }

    open func removeDelegates() {
        delegates.removeAllObjects()
    }
}

@discardableResult
public func +=<T>(left: MulticastDelegate<T>, right: T) -> MulticastDelegate<T> {
    left.addDelegate(right)
    return left
}

@discardableResult
public func -=<T>(left: MulticastDelegate<T>, right: T) -> MulticastDelegate<T> {
    left.removeDelegate(right)
    return left
}


//infix  operator |> { associativity left precedence 130 }
precedencegroup DefaultPrecedence {
    associativity: left
    higherThan: TernaryPrecedence
}

infix operator |> : DefaultPrecedence

@discardableResult
public func |><T>(left: MulticastDelegate<T>, right: (T) -> ()) -> MulticastDelegate<T> {
    left.invokeDelegates(right)
    return left
}
