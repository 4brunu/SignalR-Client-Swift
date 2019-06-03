//
//  HubConnectionTests.swift
//  SignalRClient
//
//  Created by Pawel Kadluczka on 3/4/17.
//  Copyright © 2017 Pawel Kadluczka. All rights reserved.
//

import XCTest
@testable import SignalRClient

class HubConnectionTests: XCTestCase {

    func testThatOpeningHubConnectionFailsIfHandshakeFails() {
        // This test fails most of the times when running against SignalR Service - the webSocket is closed
        // before receiving any data. Occasionally when data is being received before close the data is correct.
        // This is a negative test so leaving as is for now.
        let didFailToOpenExpectation = expectation(description: "connection failed to open")
        let didCloseExpectation = expectation(description: "connection closed")

        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = { _ in XCTFail() }
        hubConnectionDelegate.connectionDidFailToOpenHandler = { error in
            didFailToOpenExpectation.fulfill()
            switch (error as? SignalRError) {
            case .handshakeError(let errorMessage)?:
                XCTAssertEqual("The protocol 'fakeProtocol' is not supported.", errorMessage)
                break
            default:
                XCTFail()
                break
            }
        }
        hubConnectionDelegate.connectionDidCloseHandler = { error in
            didCloseExpectation.fulfill()
            XCTAssertNil(error)
        }

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!)
            .withLogging(minLogLevel: .debug)
            .withHubProtocol(hubProtocolFactory: {_ in HubProtocolFake()})
            .build()
        hubConnection.delegate = hubConnectionDelegate
        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testThatHubMethodCanBeInvoked() {
        let didOpenExpectation = expectation(description: "connection opened")
        let didReceiveInvocationResult = expectation(description: "received invocation result")
        let didCloseExpectation = expectation(description: "connection closed")

        let message = "Hello, World!"
        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = { hubConnection in
            didOpenExpectation.fulfill()

            hubConnection.invoke(method: "Echo", arguments: [message], returnType: String.self) {result, error in
                XCTAssertNil(error)
                XCTAssertEqual(message, result)
                didReceiveInvocationResult.fulfill()
                hubConnection.stop()
            }
        }

        hubConnectionDelegate.connectionDidCloseHandler = { error in
            XCTAssertNil(error)
            didCloseExpectation.fulfill()
        }

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!).build()
        hubConnection.delegate = hubConnectionDelegate
        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testTestThatInvokingHubMethodRetunsErrorIfInvokedBeforeHandshakeReceived() {
        let didComplete = expectation(description: "test completed")

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!).build()
        hubConnection.start()
        hubConnection.invoke(method: "x", arguments: [], returnType: String.self) {result, error in
            XCTAssertNotNil(error)
            XCTAssertEqual("\(SignalRError.invalidOperation(message: "Attempting to send data before connection has been started."))", "\(error!)")
            hubConnection.stop()
            didComplete.fulfill()
        }

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testThatVoidHubMethodCanBeInvoked() {
        let didOpenExpectation = expectation(description: "connection opened")
        let didReceiveInvocationResult = expectation(description: "received invocation result")
        let didCloseExpectation = expectation(description: "connection closed")

        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = { hubConnection in
            didOpenExpectation.fulfill()

            hubConnection.invoke(method: "VoidMethod", arguments: [], invocationDidComplete: { error in
                XCTAssertNil(error)
                didReceiveInvocationResult.fulfill()
                hubConnection.stop()
            })
        }

        hubConnectionDelegate.connectionDidCloseHandler = { error in
            XCTAssertNil(error)
            didCloseExpectation.fulfill()
        }

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!).build()
        hubConnection.delegate = hubConnectionDelegate
        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testTestThatInvokingVoidHubMethodRetunsErrorIfInvokedBeforeHandshakeReceived() {
        let didComplete = expectation(description: "test completed")

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!).build()
        hubConnection.start()
        hubConnection.invoke(method: "x", arguments: []) {error in
            XCTAssertNotNil(error)
            XCTAssertEqual("\(SignalRError.invalidOperation(message: "Attempting to send data before connection has been started."))", "\(error!)")
            hubConnection.stop()
            didComplete.fulfill()
        }

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testThatExceptionsInHubMethodsAreTurnedIntoErrors() {
        let didOpenExpectation = expectation(description: "connection opened")
        let didReceiveInvocationResult = expectation(description: "received invocation result")
        let didCloseExpectation = expectation(description: "connection closed")

        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = { hubConnection in
            didOpenExpectation.fulfill()

            hubConnection.invoke(method: "ErrorMethod", arguments: [], returnType: String.self, invocationDidComplete: { result, error in
                XCTAssertNotNil(error)

                switch (error as! SignalRError) {
                case .hubInvocationError(let errorMessage):
                    XCTAssertEqual("An unexpected error occurred invoking 'ErrorMethod' on the server. InvalidOperationException: Error occurred.", errorMessage)
                    break
                default:
                    XCTFail()
                    break
                }

                didReceiveInvocationResult.fulfill()
                hubConnection.stop()
            })
        }

        hubConnectionDelegate.connectionDidCloseHandler = { error in
            XCTAssertNil(error)
            didCloseExpectation.fulfill()
        }

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!).build()
        hubConnection.delegate = hubConnectionDelegate
        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testThatPendingInvocationsAreCancelledWhenConnectionIsClosed() {
        let invocationCancelledExpectation = expectation(description: "invocation cancelled")

        let testConnection = TestConnection()
        let logger = PrintLogger()
        let hubConnection = HubConnection(connection: testConnection, hubProtocol: JSONHubProtocol(logger: logger), logger: logger)
        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = { hubConnection in
            hubConnection.invoke(method: "TestMethod", arguments: [], invocationDidComplete: { error in
                XCTAssertNotNil(error)

                switch (error as! SignalRError) {
                case .hubInvocationCancelled:
                    invocationCancelledExpectation.fulfill()
                    break
                default:
                    XCTFail()
                    break
                }
            })

            hubConnection.stop()
        }

        hubConnection.delegate = hubConnectionDelegate
        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testThatPendingInvocationsAreAbortedWhenConnectionIsClosedWithError() {
        let invocationCancelledExpectation = expectation(description: "invocation cancelled")
        let testError = SignalRError.invalidOperation(message: "testError")

        let testConnection = TestConnection()
        let hubConnection = HubConnection(connection: testConnection, hubProtocol: JSONHubProtocol(logger: NullLogger()))
        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnection.delegate = hubConnectionDelegate
        hubConnectionDelegate.connectionDidOpenHandler = { hubConnection in
            hubConnection.invoke(method: "TestMethod", arguments: [], invocationDidComplete: { error in
                switch (error as! SignalRError) {
                case .invalidOperation(let errorMessage):
                    XCTAssertEqual("testError", errorMessage)
                    break
                default:
                    XCTFail()
                    break
                }
                invocationCancelledExpectation.fulfill()
            })
            testConnection.delegate?.connectionDidClose(error: testError)
        }

        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testThatStreamingHubMethodCanBeInvoked() {
        let didOpenExpectation = expectation(description: "connection opened")
        let didReceiveStreamItems = expectation(description: "received stream items")
        let didCloseExpectation = expectation(description: "connection closed")
        var items: [Int] = []

        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = { hubConnection in
            didOpenExpectation.fulfill()

            _ = hubConnection.stream(method: "StreamNumbers", arguments: [10, 1], itemType: Int.self, streamItemReceived: { item in items.append(item!) }, invocationDidComplete: { error in
                XCTAssertNil(error)
                XCTAssertEqual([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], items)
                didReceiveStreamItems.fulfill()
                hubConnection.stop()
            })
        }

        hubConnectionDelegate.connectionDidCloseHandler = { error in
            XCTAssertNil(error)
            didCloseExpectation.fulfill()
        }

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!).build()
        hubConnection.delegate = hubConnectionDelegate
        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testTestThatInvokingStreamingMethodRetunsErrorIfInvokedBeforeHandshakeReceived() {
        let didComplete = expectation(description: "test completed")

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!).build()
        hubConnection.start()
        _ = hubConnection.stream(method: "StreamNumbers", arguments: [], itemType: Int.self, streamItemReceived: {_ in }, invocationDidComplete: {error in
            XCTAssertNotNil(error)
            XCTAssertEqual("\(SignalRError.invalidOperation(message: "Attempting to send data before connection has been started."))", "\(error!)")
            hubConnection.stop()
            didComplete.fulfill()
        })

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testThatExceptionsInHubStreamingMethodsCloseStreamWithError() {
        let didOpenExpectation = expectation(description: "connection opened")
        let didReceiveInvocationError = expectation(description: "received invocation error")
        let didCloseExpectation = expectation(description: "connection closed")

        var receivedItems: [String?] = []
        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = { hubConnection in
            didOpenExpectation.fulfill()

            _ = hubConnection.stream(method: "ErrorStreamMethod", arguments: [], itemType: String.self, streamItemReceived: { item in receivedItems.append(item)} , invocationDidComplete: { error in
                XCTAssertNotNil(error)

                switch (error as! SignalRError) {
                case .hubInvocationError(let errorMessage):
                    XCTAssertEqual("An error occurred on the server while streaming results. InvalidOperationException: Error occurred while streaming.", errorMessage)
                    break
                default:
                    XCTFail()
                    break
                }

                XCTAssertEqual(2, receivedItems.count)
                XCTAssertEqual("abc", receivedItems[0])
                XCTAssertEqual(nil, receivedItems[1])
                didReceiveInvocationError.fulfill()
                hubConnection.stop()
            })
        }

        hubConnectionDelegate.connectionDidCloseHandler = { error in
            XCTAssertNil(error)
            didCloseExpectation.fulfill()
        }

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!).build()
        hubConnection.delegate = hubConnectionDelegate
        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testThatExceptionsWhileProcessingStreamItemCloseStreamWithError() {
        let didOpenExpectation = expectation(description: "connection opened")
        let didReceiveInvocationError = expectation(description: "received invocation error")
        let didCloseExpectation = expectation(description: "connection closed")

        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = { hubConnection in
            didOpenExpectation.fulfill()

            _ = hubConnection.stream(method: "StreamNumbers", arguments: [5, 5], itemType: UUID.self, streamItemReceived: { item in XCTFail() } , invocationDidComplete: { error in
                XCTAssertNotNil(error)
                switch (error as! SignalRError) {
                case .unsupportedType:
                    break
                default:
                    XCTFail()
                    break
                }

                didReceiveInvocationError.fulfill()
                hubConnection.stop()
            })
        }

        hubConnectionDelegate.connectionDidCloseHandler = { error in
            XCTAssertNil(error)
            didCloseExpectation.fulfill()
        }

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!).build()
        hubConnection.delegate = hubConnectionDelegate
        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testThatPendingStreamInvocationsAreCancelledWhenConnectionIsClosed() {
        let invocationCancelledExpectation = expectation(description: "invocation cancelled")

        let testConnection = TestConnection()
        let hubConnection = HubConnection(connection: testConnection, hubProtocol: JSONHubProtocol(logger: NullLogger()))
        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = {hubConnection in
            _ = hubConnection.stream(method: "StreamNumbers", arguments: [5, 100], itemType: Int.self, streamItemReceived: { item in }, invocationDidComplete: { error in
                XCTAssertNotNil(error)

                switch (error as! SignalRError) {
                case .hubInvocationCancelled:
                    invocationCancelledExpectation.fulfill()
                    break
                default:
                    XCTFail()
                    break
                }
            })
            hubConnection.stop()
        }
        hubConnection.delegate = hubConnectionDelegate
        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testThatPendingStreamInvocationsAreAbortedWhenConnectionIsClosedWithError() {
        let invocationCancelledExpectation = expectation(description: "invocation cancelled")
        let testError = SignalRError.invalidOperation(message: "testError")

        let testConnection = TestConnection()
        let hubConnection = HubConnection(connection: testConnection, hubProtocol: JSONHubProtocol(logger: NullLogger()))
        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = {hubConnection in
            _ = hubConnection.stream(method: "StreamNumbers", arguments: [5, 100], itemType: Int.self, streamItemReceived: { item in }, invocationDidComplete: { error in
                switch (error as! SignalRError) {
                case .invalidOperation(let errorMessage):
                    XCTAssertEqual("testError", errorMessage)
                    break
                default:
                    XCTFail()
                    break
                }
                invocationCancelledExpectation.fulfill()
            })
            testConnection.delegate?.connectionDidClose(error: testError)
        }
        hubConnection.delegate = hubConnectionDelegate
        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testThatCanCancelStreamingInvocations() {
        let didOpenExpectation = expectation(description: "connection opened")
        let didCloseExpectation = expectation(description: "connection closed")

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!).build()
        var lastItem = -1
        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = { hubConnection in
            didOpenExpectation.fulfill()

            var streamHandle: StreamHandle? = nil
            streamHandle = hubConnection.stream(method: "StreamNumbers", arguments: [1000, 1], itemType: Int.self, streamItemReceived: { item in
                lastItem = item!
                if item == 42 {
                    hubConnection.cancelStreamInvocation(streamHandle: streamHandle!, cancelDidFail: { _ in XCTFail() })
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        hubConnection.stop()
                    }
                }
            }, invocationDidComplete: { _ in XCTFail() })
        }

        hubConnectionDelegate.connectionDidCloseHandler = { error in
            XCTAssertNil(error)
            XCTAssert(lastItem < 50)
            didCloseExpectation.fulfill()
        }

        hubConnection.delegate = hubConnectionDelegate
        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testThatCancellingStreamingInvocationSendsCancelStreamMessage() {
        var messages: [Data] = []

        let testConnection = TestConnection()
        testConnection.sendDelegate = { data, sendDidComplete in
            messages.append(data)
            sendDidComplete(nil)
        }

        let hubConnection = HubConnection(connection: testConnection, hubProtocol: JSONHubProtocol(logger: NullLogger()))
        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnection.delegate = hubConnectionDelegate
        hubConnectionDelegate.connectionDidOpenHandler = {hubConnection in
            let streamHandle = hubConnection.stream(method: "TestStream", arguments: [], itemType: Int.self,
                                                    streamItemReceived: { _ in XCTFail() },
                                                    invocationDidComplete: { _ in XCTFail() })
            hubConnection.cancelStreamInvocation(streamHandle: streamHandle, cancelDidFail: { _ in XCTFail() })

            hubConnection.stop()

            // 3 messages: protocol negotation/handshake, stream method invocation, stream method cancellation
            XCTAssertEqual(3, messages.count)
            let methodCancellationJson = try! JSONSerialization.jsonObject(with: messages.last!.split(separator: 0x1e).first!) as! [String: Any]
            XCTAssertEqual(2, methodCancellationJson.count)
            XCTAssertEqual(5, methodCancellationJson["type"] as! Int)
            XCTAssertEqual("1", methodCancellationJson["invocationId"] as! String)
        }
        hubConnection.start()
    }

    func testThatCallbackInvokedIfSendingCancellationMessageFailed() {
        let cancelDidFailExpectation = expectation(description: "cancelDidFail invoked")

        let testConnection = TestConnection()
        testConnection.sendDelegate = { data, sendDidComplete in
            let msg = String(data: data, encoding: .utf8)!
            sendDidComplete(msg.contains("\"type\":5") ? SignalRError.invalidOperation(message: "test") : nil)
        }

        let hubConnection = HubConnection(connection: testConnection, hubProtocol: JSONHubProtocol(logger: NullLogger()))
        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = {hubConnection in
            let streamHandle = hubConnection.stream(method: "TestStream", arguments: [], itemType: Int.self,
                                                    streamItemReceived: { _ in XCTFail() },
                                                    invocationDidComplete: { _ in XCTFail() })
            hubConnection.cancelStreamInvocation(streamHandle: streamHandle, cancelDidFail: { error in
                switch (error as! SignalRError) {
                case .invalidOperation(let errorMessage):
                    XCTAssertEqual("test", errorMessage)
                    break
                default:
                    XCTFail()
                    break
                }
                hubConnection.stop()
                cancelDidFailExpectation.fulfill()
            })
        }
        hubConnection.delegate = hubConnectionDelegate
        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testTestThatCancellingStreamingInvocationRetunsErrorIfInvokedBeforeHandshakeReceived() {
        let didComplete = expectation(description: "test completed")

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!).build()
        hubConnection.start()
        hubConnection.cancelStreamInvocation(streamHandle: StreamHandle(invocationId: "123")) {error in
            XCTAssertEqual("\(SignalRError.invalidOperation(message: "Attempting to send data before connection has been started."))", "\(error)")
            hubConnection.stop()
            didComplete.fulfill()
        }

        waitForExpectations(timeout: 5 /*seconds*/)
    }
    
    func testTestThatCancellingStreamingInvocationWithInvalidStreamHandleRetunsErrorIfInvokedBeforeHandshakeReceived() {
        let didComplete = expectation(description: "test completed")

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!).build()
        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = {hubConnection in
            hubConnection.cancelStreamInvocation(streamHandle: StreamHandle(invocationId: "")) {error in
                XCTAssertEqual("\(SignalRError.invalidOperation(message: "Invalid stream handle."))", "\(error)")
                hubConnection.stop()
                didComplete.fulfill()
            }
        }
        hubConnection.delegate = hubConnectionDelegate
        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testThatClientMethodsCanBeInvoked() {
        let didOpenExpectation = expectation(description: "connection opened")
        let didReceiveInvocationResult = expectation(description: "received invocation result")
        let didInvokeClientMethod = expectation(description: "client method invoked")
        let didCloseExpectation = expectation(description: "connection closed")

        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = { hubConnection in
            didOpenExpectation.fulfill()

            hubConnection.invoke(method: "InvokeGetNumber", arguments: [42], invocationDidComplete: { error in
                XCTAssertNil(error)
                didReceiveInvocationResult.fulfill()
            })
        }

        hubConnectionDelegate.connectionDidCloseHandler = { error in
            XCTAssertNil(error)
            didCloseExpectation.fulfill()
        }

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!)
            .withLogging(minLogLevel: .debug)
            .build()
        hubConnection.delegate = hubConnectionDelegate
        hubConnection.on(method: "GetNumber", callback: { args, _ in
            XCTAssertNotNil(args)
            XCTAssertEqual(1, args.count)
            XCTAssertEqual(42, args[0] as! Int)
            didInvokeClientMethod.fulfill()
            hubConnection.stop()
        })

        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testThatClientMethodsCanBeOverwritten() {
        let didOpenExpectation = expectation(description: "connection opened")
        let didReceiveInvocationResult = expectation(description: "received invocation result")
        let didInvokeClientMethod = expectation(description: "client method invoked")
        let didCloseExpectation = expectation(description: "connection closed")

        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = { hubConnection in
            didOpenExpectation.fulfill()

            hubConnection.invoke(method: "InvokeGetNumber", arguments: [42], invocationDidComplete: { error in
                XCTAssertNil(error)
                didReceiveInvocationResult.fulfill()
            })
        }

        hubConnectionDelegate.connectionDidCloseHandler = { error in
            XCTAssertNil(error)
            didCloseExpectation.fulfill()
        }

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!).build()
        hubConnection.delegate = hubConnectionDelegate

        hubConnection.on(method: "GetNumber", callback: { args, _ in
            XCTFail("Should not be invoked")
        })

        hubConnection.on(method: "GetNumber", callback: { args, _ in
            XCTAssertNotNil(args)
            XCTAssertEqual(1, args.count)
            XCTAssertEqual(42, args[0] as! Int)
            didInvokeClientMethod.fulfill()
            hubConnection.stop()
        })

        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testThatClientMethodsCanBeInvokedWithTypedStructuralArgument() {
        let didOpenExpectation = expectation(description: "connection opened")
        let didReceiveInvocationResult = expectation(description: "received invocation result")
        let didInvokeClientMethod = expectation(description: "client method invoked")
        let didCloseExpectation = expectation(description: "connection closed")

        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = { hubConnection in
            didOpenExpectation.fulfill()

            let person = User(firstName: "Jerzy", lastName: "Meteor", age: 34, height: 179.0, sex: Sex.Male)
            hubConnection.invoke(method: "InvokeGetPerson", arguments: [person], invocationDidComplete: { error in
                XCTAssertNil(error)
                didReceiveInvocationResult.fulfill()
            })
        }

        hubConnectionDelegate.connectionDidCloseHandler = { error in
            XCTAssertNil(error)
            didCloseExpectation.fulfill()
        }

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!)
            .withJSONHubProtocol(typeConverter: PersonTypeConverter())
            .build()

        hubConnection.delegate = hubConnectionDelegate
        hubConnection.on(method: "GetPerson", callback: { arguments, typeConverter in
            XCTAssertNotNil(arguments)
            let person = try! typeConverter.convertFromWireType(obj: arguments[0], targetType: User.self)
            XCTAssertEqual("Jerzy", person!.firstName)
            XCTAssertEqual("Meteor", person!.lastName)
            XCTAssertEqual(34, person!.age)
            XCTAssertEqual(179.0, person!.height)
            XCTAssertEqual(Sex.Male, person!.sex)
            didInvokeClientMethod.fulfill()
            hubConnection.stop()
        })

        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testThatSendInvokesMethodsOnServer() {
        let didOpenExpectation = expectation(description: "connection opened")
        let sendCompletedExpectation = expectation(description: "send completed")
        let didInvokeClientMethod = expectation(description: "client method invoked")
        let didCloseExpectation = expectation(description: "connection closed")

        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = { hubConnection in
            didOpenExpectation.fulfill()

            hubConnection.send(method: "InvokeGetNumber", arguments: [42], sendDidComplete: { error in
                XCTAssertNil(error)
                sendCompletedExpectation.fulfill()
            })
        }

        hubConnectionDelegate.connectionDidCloseHandler = { error in
            XCTAssertNil(error)
            didCloseExpectation.fulfill()
        }

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!).build()
        hubConnection.delegate = hubConnectionDelegate
        hubConnection.on(method: "GetNumber", callback: { args, _ in
            XCTAssertNotNil(args)
            XCTAssertEqual(1, args.count)
            XCTAssertEqual(42, args[0] as! Int)
            didInvokeClientMethod.fulfill()
            hubConnection.stop()
        })

        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testTestThatSendRetunsErrorIfInvokedBeforeHandshakeReceived() {
        let didComplete = expectation(description: "test completed")

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!).build()
        hubConnection.start()
        hubConnection.send(method: "x", arguments: []) {error in
            XCTAssertNotNil(error)
            XCTAssertEqual("\(SignalRError.invalidOperation(message: "Attempting to send data before connection has been started."))", "\(error!)")
            hubConnection.stop()
            didComplete.fulfill()
        }

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    enum Sex: Int, Codable {
        case Male
        case Female
    }

    struct User: Codable {
        public let firstName: String
        let lastName: String
        let age: Int?
        let height: Double?
        let sex: Sex?
    }

    class PersonTypeConverter: JSONTypeConverter {
        override func convertToWireType(obj: Any?) throws -> Any? {
            if let user = obj as? User? {
                return convertUser(user: user)
            }

            if let users = obj as? [User?] {
                return users.map({u in convertUser(user:u)})
            }

            return try super.convertToWireType(obj: obj)
        }

        private func convertUser(user: User?) -> [String: Any?]? {
            if let u = user {
                return [
                    "firstName": u.firstName,
                    "lastName": u.lastName,
                    "age": u.age,
                    "height": u.height,
                    "sex": u.sex == Sex.Male ? 0 : 1]
            }

            return nil
        }

        override func convertFromWireType<T>(obj: Any?, targetType: T.Type) throws -> T? {
            if let userDictionary = obj as? [String: Any?]? {
                return materializeUser(userDictionary: userDictionary) as? T
            }

            if let userArray = obj as? [[String: Any?]?] {

                let result: [User?] = userArray.map({userDictionary in
                    return materializeUser(userDictionary: userDictionary)
                })

                return result as? T
            }

            return try super.convertFromWireType(obj: obj, targetType: targetType)
        }

        private func materializeUser(userDictionary: [String: Any?]?) -> User? {
            if let user = userDictionary {
                return User(firstName: user["firstName"] as! String, lastName: user["lastName"] as! String, age: user["age"] as! Int?, height: user["height"] as! Double?, sex: user["sex"] as! Int == 0 ? Sex.Male : Sex.Female)
            }
            return nil
        }
    }

    func testThatHubMethodUsingComplexTypesCanBeInvoked() {
        let didOpenExpectation = expectation(description: "connection opened")
        let didReceiveInvocationResult = expectation(description: "received invocation result")
        let didCloseExpectation = expectation(description: "connection closed")

        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = { hubConnection in
            didOpenExpectation.fulfill()

            let input = [User(firstName: "Klara", lastName: "Smetana", age: nil, height: 166.5, sex: Sex.Female),
                         User(firstName: "Jerzy", lastName: "Meteor", age: 34, height: 179.0, sex: Sex.Male)]

            hubConnection.invoke(method: "SortByName", arguments: [input], returnType: [User].self, invocationDidComplete: { people, error in
                XCTAssertNil(error)
                XCTAssertNotNil(people)
                XCTAssertEqual(2, people!.count)

                XCTAssertEqual("Jerzy", people![0].firstName)
                XCTAssertEqual("Meteor", people![0].lastName)
                XCTAssertEqual(34, people![0].age)
                XCTAssertEqual(179.0, people![0].height)
                XCTAssertEqual(Sex.Male, people![0].sex)

                XCTAssertEqual("Klara", people![1].firstName)
                XCTAssertEqual("Smetana", people![1].lastName)
                XCTAssertNil(people![1].age)
                XCTAssertEqual(166.5, people![1].height)
                XCTAssertEqual(Sex.Female, people![1].sex)

                didReceiveInvocationResult.fulfill()
                hubConnection.stop()
            })
        }

        hubConnectionDelegate.connectionDidCloseHandler = { error in
            XCTAssertNil(error)
            didCloseExpectation.fulfill()
        }

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!)
            .withJSONHubProtocol(typeConverter: PersonTypeConverter())
            .build()
        hubConnection.delegate = hubConnectionDelegate
        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testThatHubConnectionSendsHeaders() {
        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = { hubConnection in
            hubConnection.invoke(method: "GetHeader", arguments: ["TestHeader"], returnType: String.self, invocationDidComplete: { result, error in
                XCTAssertNil(error)
                XCTAssertEqual("header", result)
                hubConnection.stop()
            })
        }

        let didCloseExpectation = expectation(description: "connection closed")
        hubConnectionDelegate.connectionDidCloseHandler = { error in
            XCTAssertNil(error)
            didCloseExpectation.fulfill()
        }

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!)
            .withHttpConnectionOptions() { httpConnectionOptions in
                httpConnectionOptions.headers["TestHeader"] = "header"
            }
            .build()

        hubConnection.delegate = hubConnectionDelegate
        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testThatHubConnectionSendsAuthToken() {
        let hubConnectionDelegate = TestHubConnectionDelegate()
        hubConnectionDelegate.connectionDidOpenHandler = { hubConnection in
            hubConnection.invoke(method: "GetHeader", arguments: ["Authorization"], returnType: String.self, invocationDidComplete: { result, error in
                XCTAssertNil(error)
                XCTAssertEqual("Bearer abc", result)
                hubConnection.stop()
            })
        }

        let didCloseExpectation = expectation(description: "connection closed")
        hubConnectionDelegate.connectionDidCloseHandler = { error in
            XCTAssertNil(error)
            didCloseExpectation.fulfill()
        }

        let hubConnection = HubConnectionBuilder(url: URL(string: "\(BASE_URL)/testhub")!)
            .withHttpConnectionOptions() { httpConnectionOptions in
                httpConnectionOptions.accessTokenProvider = { return "abc" }
            }
            .build()

        hubConnection.delegate = hubConnectionDelegate
        hubConnection.start()

        waitForExpectations(timeout: 5 /*seconds*/)
    }

    func testThatStopDoesNotPassStopErrorToUnderlyingConnection() {
        class FakeHttpConnection: HttpConnection {
            var stopCalled: Bool = false

            override func stop(stopError: Error?) {
                XCTAssertNil(stopError)
                stopCalled = true
            }
        }

        let fakeConnection = FakeHttpConnection(url: URL(string: "http://fakeuri.org")!)
        let hubConnection = HubConnection(connection: fakeConnection, hubProtocol: JSONHubProtocol(logger: NullLogger()))
        hubConnection.stop()
        XCTAssertTrue(fakeConnection.stopCalled)
    }

    func testThatHubConnectionClosesConnectionUponReceivingCloseMessage() {
        class FakeHttpConnection: HttpConnection {
            var stopError: Error?

            override func start() {
                delegate?.connectionDidOpen(connection: self)
            }

            override func stop(stopError: Error?) {
                self.stopError = stopError
            }
        }

        let fakeConnection = FakeHttpConnection(url: URL(string: "http://fakeuri.org")!)
        let hubConnection = HubConnection(connection: fakeConnection, hubProtocol: JSONHubProtocol(logger: NullLogger()))
        hubConnection.start()
        let payload = "{}\u{1e}{ \"type\": 7, \"error\": \"Server Error\" }\u{1e}"
        fakeConnection.delegate.connectionDidReceiveData(connection: fakeConnection, data: payload.data(using: .utf8)!)
        XCTAssertEqual(String(describing: SignalRError.serverClose(message: "Server Error")), String(describing: fakeConnection.stopError!))
    }
}

class TestHubConnectionDelegate: HubConnectionDelegate {
    var connectionDidOpenHandler: ((_ hubConnection: HubConnection) -> Void)?
    var connectionDidFailToOpenHandler: ((_ error: Error) -> Void)?
    var connectionDidCloseHandler: ((_ error: Error?) -> Void)?

    func connectionDidOpen(hubConnection: HubConnection!) {
        connectionDidOpenHandler?(hubConnection)
    }

    func connectionDidFailToOpen(error: Error) {
        connectionDidFailToOpenHandler?(error)
    }

    func connectionDidClose(error: Error?) {
        connectionDidCloseHandler?(error)
    }
}

class TestConnection: Connection {
    var delegate: ConnectionDelegate!
    var sendDelegate: ((_ data: Data, _ sendDidComplete: (_ error: Error?) -> Void) -> Void)?

    func start() {
        delegate?.connectionDidOpen(connection: self)
        delegate?.connectionDidReceiveData(connection: self, data: "{}\u{1e}".data(using: .utf8)!)
    }

    func send(data: Data, sendDidComplete: (_ error: Error?) -> Void) {
        sendDelegate?(data, sendDidComplete)
    }

    func stop(stopError: Error? = nil) -> Void {
        delegate?.connectionDidClose(error: stopError)
    }
}
