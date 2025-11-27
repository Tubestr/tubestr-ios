//
//  CoreDataHelpers.swift
//  MyTube
//
//  Provides reusable patterns for Core Data context operations.
//

import CoreData

extension NSManagedObjectContext {
    /// Executes a throwing block synchronously and returns the result, propagating any errors.
    func performAndCapture<T>(_ block: () throws -> T) throws -> T {
        var result: T?
        var capturedError: Error?
        performAndWait {
            do {
                result = try block()
            } catch {
                capturedError = error
            }
        }
        if let error = capturedError {
            throw error
        }
        return result!
    }

    /// Executes a throwing block synchronously without returning a value, propagating any errors.
    func performAndCaptureVoid(_ block: () throws -> Void) throws {
        var capturedError: Error?
        performAndWait {
            do {
                try block()
            } catch {
                capturedError = error
            }
        }
        if let error = capturedError {
            throw error
        }
    }
}
