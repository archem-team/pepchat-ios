//
//  Http.swift
//  Revolt
//
//  Created by Zomatree on 21/04/2023.
//

import Foundation
import Alamofire
import Types
import OSLog

///You can connect to the API on the following URLs:
///https://developers.revolt.chat/developers/endpoints.html
///Primary API endpoint ---> https://api.revolt.chat (Production)
///API endpoint for old client ---> https://app.revolt.chat/api (Production)
///API endpoint for peptide ---> https://peptide.chat/api (Production)
///You can connect to the events server on the following URLs:
///Primary events endpoint--->  wss://ws.revolt.chat (Production)
///Events endpoint for old client--->  wss://app.revolt.chat/events   (Production)
///Events endpoint for peptide ---> wss://peptide.chat/ws

//peptide

// MARK: - Custom Errors
struct TimeoutError: Error {
    let message: String
    
    init(_ message: String = "Request timed out") {
        self.message = message
    }
}

// Enumeration representing different types of errors that can occur during an HTTP request in the Revolt application.
enum RevoltError: Error {
    case Alamofire(AFError) // Error related to Alamofire network library
    case HTTPError(String?, Int) // HTTP error containing a message and status code
    case JSONDecoding(any Error) // Error encountered during JSON decoding
}

// Structure that represents an HTTP client for handling network requests within the Revolt application.
struct HTTPClient {
    var token: String? // Optional session token for authentication
    var baseURL: String // Base URL for Revolt's API endpoints
    var apiInfo: ApiInfo? // Information about the Revolt API
    var session: Alamofire.Session // Alamofire session for managing network requests
    var logger: Logger // Logger used for logging HTTP request responses and errors
    weak var viewState: ViewState? // Weak reference to ViewState for immediate local updates
    
    // Initializer for HTTPClient, taking in an optional token and a base URL.
    init(token: String?, baseURL: String, viewState: ViewState? = nil) {
        self.token = token
        self.baseURL = baseURL
        self.apiInfo = nil
        
        // Configure URLSessionConfiguration to reduce network warnings
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10.0  // Reduced from 30 to 10 seconds
        configuration.timeoutIntervalForResource = 20.0  // Reduced from 60 to 20 seconds
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 2  // Reduced from 4 to minimize connection issues
        configuration.waitsForConnectivity = false  // Don't wait for connectivity - fail fast
        configuration.allowsConstrainedNetworkAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        
        // NETWORK OPTIMIZATION: Reduce connection warnings
        configuration.httpShouldUsePipelining = false  // Disable pipelining to prevent connection issues
        configuration.httpShouldSetCookies = false     // Disable cookies for API calls
        configuration.httpCookieAcceptPolicy = .never  // No cookies needed
        configuration.networkServiceType = .responsiveData  // Use responsive data for faster API calls
        configuration.shouldUseExtendedBackgroundIdleMode = false  // Prevent background connection issues
        
        // CONNECTION MANAGEMENT: Prevent unconnected endpoint warnings
        configuration.multipathServiceType = .none     // Disable multipath to reduce connection complexity
        configuration.httpAdditionalHeaders = [
            "Connection": "close"  // Force connection closure after each request to prevent lingering connections
        ]
        
        // Create session with optimized configuration
        self.session = Alamofire.Session(configuration: configuration)
        
        self.logger = Logger(subsystem: "chat.peptide.app", category: "http")
        self.viewState = viewState
    }
    
    // Internal function that performs an HTTP request and returns a result containing either a response or a RevoltError.
    // The method is generic over the type of parameters that are passed in and supports any Encodable type.
    func innerReq<
        I: Encodable
    >(
        method: HTTPMethod, // The HTTP method (e.g., GET, POST, etc.)
        route: String, // API route to call
        parameters: I? = nil as Int?, // Optional parameters for the request (default is nil)
        encoder: ParameterEncoder = JSONParameterEncoder.default, // Encoder for request parameters (default is JSON)
        headers hdrs: HTTPHeaders? = nil // Optional headers for the request (default is nil)
    ) async -> Result<DataResponse<String, AFError>, RevoltError> {
        var headers: HTTPHeaders = hdrs ?? HTTPHeaders()
        
        // Add session token to headers if available
        if token != nil {
            headers.add(name: "x-session-token", value: token!)
        }
        
        // Build and execute the network request
        let req = self.session.request(
            "\(baseURL)\(route)",
            method: method,
            parameters: parameters,
            encoder: encoder,
            headers: headers
        )
        
        // TIMEOUT OPTIMIZATION: Add individual request timeout
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds timeout
            req.cancel()
            throw TimeoutError()
        }
        
        // Await the serialized response with timeout protection
        let response: DataResponse<String, AFError>
        do {
            response = await req.serializingString().response
            timeoutTask.cancel() // Cancel timeout if request completes
        } catch {
            timeoutTask.cancel()
            print("❌ REQUEST_TIMEOUT: \(method.rawValue) \(route) timed out after 15 seconds")
            return .failure(.HTTPError("Request timed out", 408))
        }
        
        let code = response.response?.statusCode ?? 500 // Default to status code 500 if unavailable
        
        if response.data == nil || response.data?.isEmpty == true {
            logger.debug("Response data is nil or empty for route \(method.rawValue) \(route) with status code \(code)")
            if [200, 201, 202, 203, 204, 205, 206, 207, 208, 226].contains(code) {
                return .success(
                    DataResponse(
                        request: response.request,
                        response: response.response,
                        data: response.data,
                        metrics: response.metrics,
                        serializationDuration: 0,
                        result: .success("")
                    )
                )
            } else {
                return .failure(.HTTPError("Empty or nil response", code))
            }
        }
        
        // Logging the response based on success or failure
        do {
            let resp = try response.result.get()
            logger.debug("OK:    Received response \(code) for route \(method.rawValue) \(baseURL)\(route) with result \(resp)")
        } catch {
            logger.debug("Error: Received response \(code) for route \(method.rawValue) \(baseURL)\(route) with result \(response.error)")
        }
        
        // Return an error if the status code is not within the successful range (2xx)
        if ![200, 201, 202, 203, 204, 205, 206, 207, 208, 226].contains(code) {
            return .failure(.HTTPError(response.value, code))
        }
        
        // Return the successful response
        return .success(response)
    }
    
    // Generic function that performs an HTTP request and decodes the result into a specific type O.
    // It is generic over both the input parameters and the output type.
    func req<
        I: Encodable,
        O: Decodable
    >(
        method: HTTPMethod, // HTTP method (e.g., GET, POST)
        route: String, // API route
        parameters: I? = nil as Int?, // Request parameters (optional)
        encoder: ParameterEncoder = JSONParameterEncoder.default, // Parameter encoder (default is JSON)
        headers: HTTPHeaders? = nil // Headers (optional)
    ) async -> Result<O, RevoltError> {
        // Perform the inner request and handle the result
        return await innerReq(method: method, route: route, parameters: parameters, encoder: encoder, headers: headers).flatMap { response in
            if let error = response.error {
                return .failure(.Alamofire(error)) // Return Alamofire error if present
            } else if let data = response.data {
                do {
                    return .success(try JSONDecoder().decode(O.self, from: data)) // Decode JSON response to type O
                } catch {
                    return .failure(.JSONDecoding(error)) // Handle JSON decoding error
                }
            } else {
                return .failure(.HTTPError("No error or body", 0)) // Handle case where no response or error is returned
            }
        }
    }
    
    // Another version of the `req` function, tailored for cases where the response does not contain a body.
    // Instead of decoding the result, it returns an `EmptyResponse` on success.
    func req<
        I: Encodable
    >(
        method: HTTPMethod,
        route: String,
        parameters: I? = nil as Int?,
        encoder: ParameterEncoder = JSONParameterEncoder.default,
        headers: HTTPHeaders? = nil
    ) async -> Result<EmptyResponse, RevoltError> {
        return await innerReq(method: method, route: route, parameters: parameters, encoder: encoder, headers: headers).flatMap { response in
            if let error = response.error {
                return .failure(.Alamofire(error))
            } else {
                return .success(EmptyResponse())
            }
        }
    }
    
    // Fetches the current user's information.
    // - Returns: A result containing a `User` object representing the current user if successful, or a `RevoltError` if an error occurs.
    func fetchSelf() async -> Result<User, RevoltError> {
        await req(method: .get, route: "/users/@me")
    }
    
    func updateSelf(profile : ProfilePayload) async -> Result<User, RevoltError> {
        await req(method: .patch, route: "/users/@me", parameters: profile)
    }
    
    // Signs out the current user and ends their session.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func signout() async -> Result<EmptyResponse, RevoltError> {
        await req(method: .post, route: "/auth/session/logout")
    }
    
    // Fetches information about the API, such as available features and endpoints.
    // - Returns: A result containing an `ApiInfo` object if successful, or a `RevoltError` if an error occurs.
    func fetchApiInfo() async -> Result<ApiInfo, RevoltError> {
        await req(method: .get, route: "/")
    }
    
    // Sends a message to the given channel, optionally including replies and attachments.
    // - Parameters:
    //   - channel: The ID of the channel to send the message to.
    //   - replies: An array of replies to include with the message.
    //   - content: The text content of the message.
    //   - attachments: An array of tuples containing file data and file names for the message attachments.
    //   - nonce: A unique identifier for the message to prevent duplicate submissions.
    // - Returns: A result containing a `Message` object if successful, or a `RevoltError` if an error occurs.
    func sendMessage(channel: String, replies: [ApiReply], content: String, attachments: [(Data, String)], nonce: String, progressCallback: ((String, Double) -> Void)? = nil) async -> Result<Message, RevoltError> {
        var attachmentIds: [String] = []
        
        for attachment in attachments {
            // Report start of upload
            progressCallback?(attachment.1, 0.0)
            
            let uploadResult = await uploadFileWithProgress(data: attachment.0, name: attachment.1, category: .attachment) { progress in
                progressCallback?(attachment.1, progress)
            }
            
            switch uploadResult {
            case .success(let response):
                attachmentIds.append(response.id)
                // Report completion
                progressCallback?(attachment.1, 1.0)
            case .failure(let error):
                // If any attachment fails to upload, return the error
                print("Failed to upload attachment '\(attachment.1)': \(error)")
                return .failure(error)
            }
        }
        
        return await req(method: .post, route: "/channels/\(channel)/messages", parameters: SendMessage(replies: replies, content: content, attachments: attachmentIds))
    }
    
    
    // Fetches a user's information by their user ID.
    // - Parameters:
    //   - user: The ID of the user whose information is being fetched.
    // - Returns: A result containing a `User` object if successful, or a `RevoltError` if an error occurs.
    func fetchUser(user: String) async -> Result<User, RevoltError> {
        await req(method: .get, route: "/users/\(user)")
    }
    
    // Deletes a specified message in a given channel.
    // - Parameters:
    //   - channel: The ID of the channel where the message is located.
    //   - message: The ID of the message to be deleted.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func deleteMessage(channel: String, message: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .delete, route: "/channels/\(channel)/messages/\(message)")
    }
    
    // Fetches message history from a channel, with options for pagination and filtering.
    // - Parameters:
    //   - channel: The ID of the channel to fetch messages from.
    //   - limit: The maximum number of messages to fetch (default is 100).
    //   - before: Optional message ID to fetch messages before.
    //   - after: Optional message ID to fetch messages after.
    //   - nearby: Optional message ID to fetch messages around (both before and after).
    //   - sort: Optional sort direction (default is "Latest").
    //   - server: Optional server ID for fetching server-specific data.
    //   - messages: Optional array of message IDs to include.
    //   - include_users: Optional flag to include user data (default is true).
    // - Returns: A result containing a `FetchHistory` object if successful, or a `RevoltError` if an error occurs.
    func fetchHistory(channel: String, limit: Int = 100, before: String? = nil, after: String? = nil, nearby: String? = nil, sort: String = "Latest", server: String? = nil, messages: [String] = [], include_users: Bool = true) async -> Result<FetchHistory, RevoltError> {
        
        // RETRY MECHANISM: Try up to 3 times with exponential backoff
        let maxRetries = 3
        var lastError: RevoltError?
        
        for attempt in 0..<maxRetries {
            let startTime = Date()
            print("⏱️ FETCH_HISTORY_ATTEMPT [\(attempt + 1)/\(maxRetries)]: Starting at \(startTime.timeIntervalSince1970)")
            
            let result = await performFetchHistory(
                channel: channel,
                limit: limit,
                before: before,
                after: after,
                nearby: nearby,
                sort: sort,
                server: server,
                messages: messages,
                include_users: include_users
            )
            
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            print("⏱️ FETCH_HISTORY_ATTEMPT [\(attempt + 1)/\(maxRetries)]: Completed in \(String(format: "%.2f", duration))s")
            
            switch result {
            case .success(let fetchHistory):
                print("✅ FETCH_HISTORY_SUCCESS: Attempt \(attempt + 1) succeeded with \(fetchHistory.messages.count) messages")
                return .success(fetchHistory)
                
            case .failure(let error):
                lastError = error
                print("❌ FETCH_HISTORY_FAILED: Attempt \(attempt + 1) failed: \(error)")
                
                // If this is the last attempt, return the error
                if attempt == maxRetries - 1 {
                    print("❌ FETCH_HISTORY_EXHAUSTED: All \(maxRetries) attempts failed")
                    break
                }
                
                // Exponential backoff: 1s, 2s, 4s
                let delay = pow(2.0, Double(attempt))
                print("⏳ FETCH_HISTORY_RETRY: Waiting \(String(format: "%.1f", delay))s before retry...")
                
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        return .failure(lastError ?? .HTTPError("Unknown error after retries", 0))
    }
    
    // Helper function that performs the actual fetchHistory request
    private func performFetchHistory(channel: String, limit: Int, before: String?, after: String?, nearby: String?, sort: String, server: String?, messages: [String], include_users: Bool) async -> Result<FetchHistory, RevoltError> {
        // Create URL components for the request
        var urlComponents = URLComponents(string: "\(baseURL)/channels/\(channel)/messages")!
        
        // Build query items from parameters
        var queryItems: [URLQueryItem] = []
        
        // Add required parameters
        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        queryItems.append(URLQueryItem(name: "include_users", value: String(include_users)))
        
        // Add optional parameters if they exist
        if let before = before {
            queryItems.append(URLQueryItem(name: "before", value: before))
        }
        
        if let after = after {
            queryItems.append(URLQueryItem(name: "after", value: after))
        }
        
        if let nearby = nearby {
            queryItems.append(URLQueryItem(name: "nearby", value: nearby))
        }
        
        if let server = server {
            queryItems.append(URLQueryItem(name: "server", value: server))
        }
        
        // Add sort parameter only if nearby is not specified
        // nearby parameter already handles message ordering, so sort is not needed
        if nearby == nil {
            queryItems.append(URLQueryItem(name: "sort", value: sort))
        }
        
        // Add message IDs if present
        if !messages.isEmpty {
            for message in messages {
                queryItems.append(URLQueryItem(name: "messages", value: message))
            }
        }
        
        // Set the query items to the URL components
        urlComponents.queryItems = queryItems
        
        // Create a custom request using the URL with query parameters
        var headers: HTTPHeaders = HTTPHeaders()
        if token != nil {
            headers.add(name: "x-session-token", value: token!)
        }
        
        // Use the URL string from our components
        guard let url = urlComponents.url?.absoluteString else {
            return .failure(.HTTPError("Invalid URL", 0))
        }
        
        // Make the request without parameters (they're in the URL)
        return await req(method: .get, route: url.replacingOccurrences(of: baseURL, with: ""))
    }
    
    // Fetches a specific message by its ID from a channel
    // - Parameters:
    //   - channel: The ID of the channel containing the message
    //   - message: The ID of the message to fetch
    // - Returns: A result containing the `Message` object if successful, or a `RevoltError` if an error occurs
    func fetchMessage(channel: String, message: String) async -> Result<Message, RevoltError> {
        await req(method: .get, route: "/channels/\(channel)/messages/\(message)")
    }
    
    // Fetches the user's direct message channels.
    // - Returns: A result containing an array of `Channel` objects if successful, or a `RevoltError` if an error occurs.
    func fetchDms() async -> Result<[Channel], RevoltError> {
        await req(method: .get, route: "/users/dms")
    }
    
    // Fetches a user's profile information by their user ID.
    // - Parameters:
    //   - user: The ID of the user whose profile is being fetched.
    // - Returns: A result containing a `Profile` object if successful, or a `RevoltError` if an error occurs.
    func fetchProfile(user: String) async -> Result<Profile, RevoltError> {
        await req(method: .get, route: "/users/\(user)/profile")
    }
    
    // Uploads a file to the server.
    // - Parameters:
    //   - data: The file data to be uploaded.
    //   - name: The name of the file being uploaded.
    //   - category: The category of the file (e.g., attachment, image).
    // - Returns: A result containing an `AutumnResponse` object if successful, or a `RevoltError` if an error occurs.
    func uploadFile(data: Data, name: String, category: FileCategory) async -> Result<AutumnResponse, RevoltError> {
        let url = "\(apiInfo!.features.autumn.url)/\(category.rawValue)"
        
        return await session.upload(
            multipartFormData: { form in form.append(data, withName: "file", fileName: name)},
            to: url
        )
        .serializingDecodable(decoder: JSONDecoder())
        .response
        .result
        .mapError(RevoltError.Alamofire)
    }
    
    // Upload file with progress tracking
    func uploadFileWithProgress(data: Data, name: String, category: FileCategory, progressCallback: @escaping (Double) -> Void) async -> Result<AutumnResponse, RevoltError> {
        let url = "\(apiInfo!.features.autumn.url)/\(category.rawValue)"
        
        return await withCheckedContinuation { continuation in
            let request = session.upload(
                multipartFormData: { form in 
                    form.append(data, withName: "file", fileName: name)
                },
                to: url
            )
            .uploadProgress { progress in
                DispatchQueue.main.async {
                    progressCallback(progress.fractionCompleted)
                }
            }
            .serializingDecodable(AutumnResponse.self, decoder: JSONDecoder())
            
            Task {
                let result = await request.response.result.mapError(RevoltError.Alamofire)
                continuation.resume(returning: result)
            }
        }
    }
    
    
    // Fetches all user sessions for authentication.
    // - Returns: A result containing an array of `Types.Session` objects if successful, or a `RevoltError` if an error occurs.
    func fetchSessions() async -> Result<[Types.Session], RevoltError> {
        await req(method: .get, route: "/auth/session/all")
    }
    
    func deleteAllOtherSessions() async -> Result<[Types.Session], RevoltError> {
        await req(method: .delete, route: "/auth/session/all")
    }
    
    // Deletes a specific user session by its ID.
    // - Parameters:
    //   - session: The ID of the session to be deleted.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func deleteSession(session: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .delete, route: "/auth/session/\(session)")
    }
    
    // Joins a server using an invite code.
    // - Parameters:
    //   - code: The invite code for the server.
    // - Returns: A result containing a `JoinResponse` if successful, or a `RevoltError` if an error occurs.
    func joinServer(code: String) async -> Result<JoinResponse, RevoltError> {
        await req(method: .post, route: "/invites/\(code)")
    }
    
    // Marks all messages in a server as read.
    // - Parameters:
    //   - serverId: The ID of the server to mark as read.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func markServerAsRead(serverId: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .put, route: "/servers/\(serverId)/ack")
    }
    
    // Reports a message for inappropriate content.
    // - Parameters:
    //   - id: The ID of the message to be reported.
    //   - reason: The reason for reporting the message.
    //   - userContext: Additional user context or comments regarding the report.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func safetyReport(type: ContentReportPayload.ContentReportType,
                      id: String,
                      reason: ContentReportPayload.ContentReportReason,
                      userContext: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .post, route: "/safety/report", parameters: ContentReportPayload(type: type, contentId: id, reason: reason, userContext: userContext))
    }
    
    // Creates a new user account.
    // - Parameters:
    //   - email: The email address for the new account.
    //   - password: The password for the new account.
    //   - invite: An optional invite code for creating the account.
    //   - captcha: An optional captcha token for verification.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func createAccount(email: String, password: String, invite: String?, captcha: String?) async -> Result<EmptyResponse, RevoltError> {
        return await req(method: .post, route: "/auth/account/create", parameters: AccountCreatePayload(email: email, password: password, invite: invite, captcha: captcha))
    }
    
    // Verifies a new account using a verification code.
    // - Parameters:
    //   - code: The verification code sent to the user's email.
    // - Returns: A result containing an `AccountCreateVerifyResponse` if successful, or a `RevoltError` if an error occurs.
    func createAccount_VerificationCode(code: String) async -> Result<AccountCreateVerifyResponse, RevoltError> {
        await req(method: .post, route: "/auth/account/verify/\(code)")
    }
    
    // Resends the verification email for account creation.
    // - Parameters:
    //   - email: The email address for which to resend the verification.
    //   - captcha: An optional captcha token for verification.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func createAccount_ResendVerification(email: String, captcha: String?) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .post, route: "/auth/account/reverify", parameters: ["email": email, "captcha": captcha])
    }
    
    // Sends a reset password email to the specified email address.
    // - Parameters:
    //   - email: The email address to send the reset password link.
    //   - captcha: An optional captcha token for verification.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func sendResetPasswordEmail(email: String, captcha: String?) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .post, route: "/auth/account/reverify", parameters: ["email": email, "captcha": captcha])
    }
    
    // Resets the user's password using a token.
    // - Parameters:
    //   - token: The reset password token received by the user.
    //   - password: The new password for the account.
    //   - removeSessions: An optional flag to indicate if all sessions should be removed (default is false).
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func resetPassword(token: String, password: String, removeSessions: Bool = false) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .patch, route: "/auth/account/reset_password", parameters: PasswordResetPayload(token: token, password: password))
    }
    
    
    // Checks the onboarding status for the user.
    // - Returns: A result containing the `OnboardingStatusResponse` if successful, or a `RevoltError` if an error occurs.
    func checkOnboarding() async -> Result<OnboardingStatusResponse, RevoltError> {
        await req(method: .get, route: "/onboard/hello")
    }
    
    // Completes the onboarding process for the user by setting a username.
    // - Parameters:
    //   - username: The username to set for the user.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func completeOnboarding(username: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .post, route: "/onboard/complete", parameters: ["username": username])
    }
    
    // Accepts a friend request from a user.
    // - Parameters:
    //   - user: The ID of the user whose friend request is being accepted.
    // - Returns: A result containing the updated `User` object if successful, or a `RevoltError` if an error occurs.
    func acceptFriendRequest(user: String) async -> Result<User, RevoltError> {
        await req(method: .put, route: "/users/\(user)/friend")
    }
    
    // Removes a user from the friends list.
    // - Parameters:
    //   - user: The ID of the user to be removed from friends.
    // - Returns: A result containing the updated `User` object if successful, or a `RevoltError` if an error occurs.
    func removeFriend(user: String) async -> Result<User, RevoltError> {
        await req(method: .delete, route: "/users/\(user)/friend")
    }
    
    // Blocks a user.
    // - Parameters:
    //   - user: The ID of the user to be blocked.
    // - Returns: A result containing the blocked `User` object if successful, or a `RevoltError` if an error occurs.
    func blockUser(user: String) async -> Result<User, RevoltError> {
        await req(method: .put, route: "/users/\(user)/block")
    }
    
    // Unblocks a user.
    // - Parameters:
    //   - user: The ID of the user to be unblocked.
    // - Returns: A result containing the unblocked `User` object if successful, or a `RevoltError` if an error occurs.
    func unblockUser(user: String) async -> Result<User, RevoltError> {
        await req(method: .delete, route: "/users/\(user)/block")
    }
    
    // Sends a friend request to a user by username.
    // - Parameters:
    //   - username: The username of the user to whom the friend request will be sent.
    // - Returns: A result containing the created `User` object if successful, or a `RevoltError` if an error occurs.
    func sendFriendRequest(username: String) async -> Result<User, RevoltError> {
        await req(method: .post, route: "/users/friend", parameters: ["username": username])
    }
    
    // Opens a direct message channel with a user.
    // - Parameters:
    //   - user: The ID of the user to open a DM channel with.
    // - Returns: A result containing the created `Channel` object if successful, or a `RevoltError` if an error occurs.
    func openDm(user: String) async -> Result<Channel, RevoltError> {
        await req(method: .get, route: "/users/\(user)/dm")
    }
    
    // Fetches unread messages for the user.
    // - Returns: A result containing an array of `Unread` objects if successful, or a `RevoltError` if an error occurs.
    func fetchUnreads() async -> Result<[Unread], RevoltError> {
        await req(method: .get, route: "/sync/unreads")
    }
    
    // Acknowledges receipt of a message in a channel.
    // - Parameters:
    //   - channel: The ID of the channel containing the message.
    //   - message: The ID of the message to acknowledge.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func ackMessage(channel: String, message: String) async -> Result<EmptyResponse, RevoltError> {
        // Add retry logic for transient network errors
        let maxRetries = 3
        var lastError: RevoltError?
        
        for attempt in 0..<maxRetries {
            let result = await req(method: .put, route: "/channels/\(channel)/ack/\(message)")
            
            switch result {
            case .success(let response):
                return .success(response)
                
            case .failure(let error):
                lastError = error
                
                // Check if it's a network error that we should retry
                if case .HTTPError(_, let code) = error {
                    // Don't retry client errors (4xx) except for 429 (rate limit)
                    if code >= 400 && code < 500 && code != 429 {
                        return .failure(error)
                    }
                } else if case .Alamofire(let afError) = error {
                    // Check if it's a network connectivity error
                    if !afError.isSessionTaskError {
                        return .failure(error)
                    }
                }
                
                // If this is the last attempt, return the error
                if attempt == maxRetries - 1 {
                    break
                }
                
                // Exponential backoff: 0.5s, 1s, 2s
                let delay = 0.5 * pow(2.0, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        return .failure(lastError ?? .HTTPError("Failed to acknowledge message after retries", 0))
    }
    
    // Creates a new group channel with a specified name and users.
    // - Parameters:
    //   - name: The name of the new group channel.
    //   - users: An array of user IDs to be included in the group.
    // - Returns: A result containing the created `Channel` object if successful, or a `RevoltError` if an error occurs.
    func createGroup(name: String, users: [String]) async -> Result<Channel, RevoltError> {
        await req(method: .post, route: "/channels/create", parameters: GroupChannelCreate(name: name, users: users))
    }
    
    func closeDMGroup(channelId : String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .delete, route: "/channels/\(channelId)")
    }
    
    
    func addMemberToGroup(groupId : String, memberId : String) async -> Result<EmptyResponse, RevoltError>{
        await req(method: .put, route: "/channels/\(groupId)/recipients/\(memberId)" )
    }
    
    
    func removeMemberFromGroup(groupId : String, memberId : String) async -> Result<EmptyResponse, RevoltError>{
        await req(method: .delete, route: "/channels/\(groupId)/recipients/\(memberId)" )
    }
    
    // Creates an invite link for a specified channel.
    // - Parameters:
    //   - channel: The ID of the channel for which to create an invite link.
    // - Returns: A result containing the created `Invite` object if successful, or a `RevoltError` if an error occurs.
    func createInvite(channel: String) async -> Result<Invite, RevoltError> {
        await req(method: .post, route: "/channels/\(channel)/invites")
    }
    
    // Fetches information about a specific member in a server.
    // - Parameters:
    //   - server: The ID of the server.
    //   - member: The ID of the member to fetch information for.
    // - Returns: A result containing the `Member` object if successful, or a `RevoltError` if an error occurs.
    func fetchMember(server: String, member: String) async -> Result<Member, RevoltError> {
        await req(method: .get, route: "/servers/\(server)/members/\(member)")
    }
    
    
    
    func fetchServerInvites(server: String) async -> Result<[Types.ServerInvite], RevoltError> {
        return await req(method: .get, route: "/servers/\(server)/invites")
    }
    
    // Edits the properties of a server.
    // - Parameters:
    //   - server: The ID of the server to edit.
    //   - edits: An object containing the edits to be made to the server.
    // - Returns: A result containing the updated `Server` object if successful, or a `RevoltError` if an error occurs.
    func editServer(server: String, edits: ServerEdit) async -> Result<Server, RevoltError> {
        await req(method: .patch, route: "/servers/\(server)", parameters: edits)
    }
    
    // Reacts to a message with a specified emoji.
    // - Parameters:
    //   - channel: The ID of the channel containing the message.
    //   - message: The ID of the message to react to.
    //   - emoji: The emoji to use for the reaction.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func reactMessage(channel: String, message: String, emoji: String) async -> Result<EmptyResponse, RevoltError> {
        let result = await req(method: .put, route: "/channels/\(channel)/messages/\(message)/reactions/\(emoji)")
        
        // Remove immediate local state update to prevent duplicates
        // The websocket event will handle the state update when the server confirms the reaction
        
        return result
    }
    
    
    // Unreacts from a message in a channel with a specified emoji.
    // - Parameters:
    //   - channel: The ID of the channel containing the message.
    //   - message: The ID of the message to unreact from.
    //   - emoji: The emoji used for the reaction to remove.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func unreactMessage(channel: String, message: String, emoji: String) async -> Result<EmptyResponse, RevoltError> {
        let result = await req(method: .delete, route: "/channels/\(channel)/messages/\(message)/reactions/\(emoji)")
        
        // Remove immediate local state update to prevent duplicates
        // The websocket event will handle the state update when the server confirms the unreaction
        
        return result
    }
    
    // Fetches the account information of the authenticated user.
    // - Returns: A result containing the `AuthAccount` object if successful, or a `RevoltError` if an error occurs.
    func fetchAccount() async -> Result<AuthAccount, RevoltError> {
        await req(method: .get, route: "/auth/account")
    }
    
    // Fetches the Multi-Factor Authentication (MFA) status for the user's account.
    // - Returns: A result containing the `AccountSettingsMFAStatus` object if successful, or a `RevoltError` if an error occurs.
    func fetchMFAStatus() async -> Result<AccountSettingsMFAStatus, RevoltError> {
        await req(method: .get, route: "/auth/mfa")
    }
    
    // Submits an MFA ticket using the user's password for authentication.
    // - Parameters:
    //   - password: The user's account password.
    // - Returns: A result containing the `MFATicketResponse` if successful, or a `RevoltError` if an error occurs.
    func submitMFATicket(password: String) async -> Result<MFATicketResponse, RevoltError> {
        await req(method: .put, route: "/auth/mfa/ticket", parameters: ["password": password])
    }
    
    // Submits an MFA ticket using a Time-Based One-Time Password (TOTP) code for authentication.
    // - Parameters:
    //   - totp: The TOTP code generated by the user's authenticator app.
    // - Returns: A result containing the `MFATicketResponse` if successful, or a `RevoltError` if an error occurs.
    func submitMFATicket(totp: String) async -> Result<MFATicketResponse, RevoltError> {
        await req(method: .put, route: "/auth/mfa/ticket", parameters: ["totp_code": totp])
    }
    
    // Submits an MFA ticket using a recovery code for authentication.
    // - Parameters:
    //   - recoveryCode: The recovery code provided to the user for MFA.
    // - Returns: A result containing the `MFATicketResponse` if successful, or a `RevoltError` if an error occurs.
    func submitMFATicket(recoveryCode: String) async -> Result<MFATicketResponse, RevoltError> {
        await req(method: .put, route: "/auth/mfa/ticket", parameters: ["recovery_code": recoveryCode])
    }
    
    func getMfaMethods() async -> Result<[MFAMethod], RevoltError> {
        await req(method: .get, route: "/auth/mfa/methods")
    }
    
    // Generates new recovery codes for the user's MFA setup.
    // - Parameters:
    //   - mfaToken: The MFA token required to authenticate the request.
    // - Returns: A result containing an array of recovery codes if successful, or a `RevoltError` if an error occurs.
    func generateRecoveryCodes(mfaToken: String) async -> Result<[String], RevoltError> {
        let headers = HTTPHeaders(dictionaryLiteral: ("X-Mfa-Ticket", mfaToken))
        return await req(method: .patch, route: "/auth/mfa/recovery", headers: headers)
    }
    
    func getRecoveryCodes(mfaToken: String) async -> Result<[String], RevoltError> {
        let headers = HTTPHeaders(dictionaryLiteral: ("X-Mfa-Ticket", mfaToken))
        return await req(method: .post, route: "/auth/mfa/recovery", headers: headers)
    }
    
    // Retrieves the TOTP secret for the user to set up MFA.
    // - Parameters:
    //   - mfaToken: The MFA token required to authenticate the request.
    // - Returns: A result containing the `TOTPSecretResponse` if successful, or a `RevoltError` if an error occurs.
    func getTOTPSecret(mfaToken: String) async -> Result<TOTPSecretResponse, RevoltError> {
        let headers = HTTPHeaders(dictionaryLiteral: ("X-Mfa-Ticket", mfaToken))
        return await req(method: .post, route: "/auth/mfa/totp", headers: headers)
    }
    
    // Enables TOTP for the user's account.
    // This should be called only after fetching the secret and verifying the user has set up the authenticator correctly.
    // - Parameters:
    //   - mfaToken: The MFA token required to authenticate the request.
    //   - totp_code: The TOTP code generated by the user's authenticator app.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func enableTOTP(mfaToken: String, totp_code: String) async -> Result<EmptyResponse, RevoltError> {
        let headers = HTTPHeaders(dictionaryLiteral: ("X-Mfa-Ticket", mfaToken))
        return await req(method: .put, route: "/auth/mfa/totp", parameters: ["totp_code": totp_code], headers: headers)
    }
    
    // Disables TOTP (Time-based One-time Password) for the user's account.
    // - Parameters:
    //   - mfaToken: The MFA token required to authenticate the request.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func disableTOTP(mfaToken: String) async -> Result<EmptyResponse, RevoltError> {
        let headers = HTTPHeaders(dictionaryLiteral: ("X-Mfa-Ticket", mfaToken))
        return await req(method: .delete, route: "/auth/mfa/totp", headers: headers)
    }
    
    // Updates the username for the authenticated user.
    // - Parameters:
    //   - newName: The new username to set for the user.
    //   - password: The user's account password to authorize the change.
    // - Returns: A result containing the updated `User` object if successful, or a `RevoltError` if an error occurs.
    func updateUsername(newName: String, password: String) async -> Result<User, RevoltError> {
        await req(method: .patch, route: "/users/@me/username", parameters: ["username": newName, "password": password])
    }
    
    
    // Updates the user's password.
    // - Parameters:
    //   - newPassword: The new password to set for the user.
    //   - oldPassword: The current password to authorize the change.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func updatePassword(newPassword: String, oldPassword: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .patch, route: "/auth/account/change/password", parameters: ["password": newPassword, "current_password": oldPassword])
    }
    
    func updateEmail(updateEmail : UpdateEmail) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .patch, route: "/auth/account/change/email", parameters: updateEmail)
    }
    
    // Disables the user's account.
    // - Parameters:
    //   - mfaToken: The MFA token required to authenticate the request.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func disableAccount(mfaToken: String) async -> Result<EmptyResponse, RevoltError> {
        let headers = HTTPHeaders(dictionaryLiteral: ("X-Mfa-Ticket", mfaToken))
        return await req(method: .post, route: "/auth/account/disable", headers: headers)
    }
    
    // Deletes the user's account.
    // - Parameters:
    //   - mfaToken: The MFA token required to authenticate the request.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func deleteAccount(mfaToken: String) async -> Result<EmptyResponse, RevoltError> {
        let headers = HTTPHeaders(dictionaryLiteral: ("X-Mfa-Ticket", mfaToken))
        return await req(method: .post, route: "/auth/account/delete", headers: headers)
    }
    
    // Edits a message in a specified channel.
    // - Parameters:
    //   - channel: The ID of the channel containing the message.
    //   - message: The ID of the message to edit.
    //   - edits: The `MessageEdit` object containing the changes to apply.
    // - Returns: A result containing the updated `Message` if successful, or a `RevoltError` if an error occurs.
    func editMessage(channel: String, message: String, edits: MessageEdit) async -> Result<Message, RevoltError> {
        await req(method: .patch, route: "/channels/\(channel)/messages/\(message)", parameters: edits)
    }
    
    // Uploads a notification token for push notifications.
    // - Parameters:
    //   - token: The notification token for the user's device.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func uploadNotificationToken(token: String) async -> Result<EmptyResponse, RevoltError> {
        // RETRY MECHANISM: Try up to 3 times with exponential backoff
        let maxRetries = 3
        var lastError: RevoltError?
        
        for attempt in 0..<maxRetries {
            print("📱 UPLOAD_NOTIFICATION_TOKEN_ATTEMPT [\(attempt + 1)/\(maxRetries)]: Attempting to upload token...")
            
            let result = await req(method: .post, route: "/push/subscribe", parameters: ["endpoint": "apn", "p256dh": "", "auth": token])
            
            switch result {
            case .success(let response):
                print("✅ UPLOAD_NOTIFICATION_TOKEN_SUCCESS: Token uploaded successfully on attempt \(attempt + 1)")
                return .success(response)
                
            case .failure(let error):
                lastError = error
                print("❌ UPLOAD_NOTIFICATION_TOKEN_FAILED: Attempt \(attempt + 1) failed: \(error)")
                
                // If this is the last attempt, return the error
                if attempt == maxRetries - 1 {
                    print("❌ UPLOAD_NOTIFICATION_TOKEN_EXHAUSTED: All \(maxRetries) attempts failed")
                    break
                }
                
                // Exponential backoff: 2s, 4s, 8s
                let delay = pow(2.0, Double(attempt + 1))
                print("⏳ UPLOAD_NOTIFICATION_TOKEN_RETRY: Waiting \(String(format: "%.1f", delay))s before retry...")
                
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        return .failure(lastError ?? .HTTPError("Failed to upload notification token after \(maxRetries) attempts", 0))
    }
    
    // Revokes the user's notification token.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func revokeNotificationToken() async -> Result<EmptyResponse, RevoltError> {
        await req(method: .post, route: "/push/unsubscribe")
    }
    
    // Searches for channels using a specified query.
    // - Parameters:
    //   - channel: The ID of the channel to search in.
    //   - query: The search query string.
    // - Returns: A result containing the `SearchResponse` if successful, or a `RevoltError` if an error occurs.
    func searchChannel(channel: String, sort : ChannelSearchPayload.MessageSort = ChannelSearchPayload.MessageSort.latest,   query: String) async -> Result<SearchResponse, RevoltError> {
        await req(method: .post, route: "/channels/\(channel)/search", parameters: ChannelSearchPayload(query: query, sort: sort, include_users: true))
    }
    
    // Fetches mutual friends with a specified user.
    // - Parameters:
    //   - user: The ID of the user to fetch mutual friends with.
    // - Returns: A result containing the `MutualsResponse` if successful, or a `RevoltError` if an error occurs.
    func fetchMutuals(user: String) async -> Result<MutualsResponse, RevoltError> {
        await req(method: .get, route: "/users/\(user)/mutual")
    }
    
    // Fetches information about a specific invite code.
    // - Parameters:
    //   - code: The invite code to retrieve information about.
    // - Returns: A result containing the `InviteInfoResponse` if successful, or a `RevoltError` if an error occurs.
    func fetchInvite(code: String) async -> Result<InviteInfoResponse, RevoltError> {
        await req(method: .get, route: "/invites/\(code)")
    }
    
    func deleteInvite(code: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .delete, route: "/invites/\(code)")
    }
    
    // Edits a role within a specified server.
    // - Parameters:
    //   - server: The ID of the server containing the role.
    //   - role: The ID of the role to edit.
    //   - payload: The `RoleEditPayload` object containing the changes to apply.
    // - Returns: A result containing the updated `Role` if successful, or a `RevoltError` if an error occurs.
    func editRole(server: String, role: String, payload: RoleEditPayload) async -> Result<Role, RevoltError> {
        await req(method: .patch, route: "/servers/\(server)/roles/\(role)", parameters: payload)
    }
    
    // Sets the permissions for a specified role within a server.
    // - Parameters:
    //   - server: The ID of the server containing the role.
    //   - role: The ID of the role to set permissions for.
    //   - permissions: The `Overwrite` object containing the permissions to apply.
    // - Returns: A result containing the updated `Server` if successful, or a `RevoltError` if an error occurs.
    func setRolePermissions(server: String, role: String, permissions: Overwrite) async -> Result<Server, RevoltError> {
        await req(method: .put, route: "/servers/\(server)/permissions/\(role)", parameters: ["permissions": ["allow": permissions.a, "deny": permissions.d]])
    }
    
    // Deletes a role from a specified server.
    // - Parameters:
    //   - server: The ID of the server containing the role.
    //   - role: The ID of the role to delete.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func deleteRole(server: String, role: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .delete, route: "/servers/\(server)/roles/\(role)")
    }
    
    // Creates a new role in a specified server.
    // - Parameters:
    //   - server: The ID of the server to create the role in.
    //   - name: The name of the new role.
    // - Returns: A result containing the newly created `RoleWithId` if successful, or a `RevoltError` if an error occurs.
    func createRole(server: String, name: String) async -> Result<RoleWithId, RevoltError> {
        await req(method: .post, route: "/servers/\(server)/roles", parameters: ["name": name])
    }
    
    // Sets the default permissions for roles in a specified server.
    // - Parameters:
    //   - server: The ID of the server to set default permissions for.
    //   - permissions: The `Permissions` object containing the default permissions to apply.
    // - Returns: A result containing the updated `Server` if successful, or a `RevoltError` if an error occurs.
    func setDefaultRolePermissions(server: String, permissions: Permissions) async -> Result<Server, RevoltError> {
        await req(method: .put, route: "/servers/\(server)/permissions/default", parameters: ["permissions": permissions])
    }
    
    // Uploads a custom emoji to a specified server.
    // - Parameters:
    //   - id: The ID of the emoji to upload.
    //   - name: The name of the emoji.
    //   - parent: The `EmojiParent` indicating where to upload the emoji.
    //   - nsfw: A boolean indicating if the emoji is NSFW (Not Safe For Work).
    // - Returns: A result containing the uploaded `Emoji` if successful, or a `RevoltError` if an error occurs.
    func uploadEmoji(id: String, name: String, parent: EmojiParent, nsfw: Bool) async -> Result<Emoji, RevoltError> {
        await req(method: .put, route: "/custom/emoji/\(id)", parameters: CreateEmojiPayload(id: id, name: name, parent: parent, nsfw: nsfw))
    }
    
    // Deletes a custom emoji.
    // - Parameters:
    //   - emoji: The ID of the emoji to delete.
    // - Returns: A result containing an `EmptyResponse` if successful, or a `RevoltError` if an error occurs.
    func deleteEmoji(emoji: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .delete, route: "/custom/emoji/\(emoji)")
    }
    
    
    func fetchBots() async -> Result<BotsResponse, RevoltError> {
        await req(method: .get, route: "/bots/@me")
    }
    
    func createBot(username: String) async -> Result<Bot, RevoltError> {
        await req(method: .post, route: "/bots/create", parameters: ["name": username])
    }
    
    func deleteBot(id: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .delete, route: "/bots/\(id)")
    }
    
    func fetchSettings(keys: [String]) async -> Result<SettingsResponse, RevoltError> {
        await req(method: .post, route: "/sync/settings/fetch", parameters: ["keys": keys])
    }
    
    func setSettings(timestamp : String,keys: [String: String]) async -> Result<SettingsResponse, RevoltError> {
        await req(method: .post, route: "/sync/settings/set?timestamp=\(timestamp)", parameters: keys)
    }
    
    func editBot(id: String, parameters: EditBotPayload) async -> Result<Bot, RevoltError> {
        await req(method: .patch, route: "/bots/\(id)", parameters: parameters)
    }
    
    func fetchBans(server: String) async -> Result<BansResponse, RevoltError> {
     await req(method: .get, route: "/servers/\(server)/bans")
     }

    func deleteBan(server: String, userId: String) async -> Result<EmptyResponse, RevoltError> {
        await req(method: .delete, route: "/servers/\(server)/bans/\(userId)")
     }
    
    func banMember(server : String, member : String, reason : String) async -> Result<Ban, RevoltError>{
        await req(method: .put, route: "/servers/\(server)/bans/\(member)", parameters: ["reason": reason])
    }
    
    func editChannel(id: String,
                     name: String? = nil,
                     description: String? = nil,
                     icon: (Data, String)? = nil,
                     nsfw: Bool? = nil,
                     owner : String? = nil,
                     remove: [ChannelEditPayload.RemoveField]? = nil) async -> Result<Channel, RevoltError>{
        
        var iconId : String?
        if let icon = icon {
            let response =  await uploadFile(data: icon.0, name: icon.1, category: .icon)
            switch response {
            case .success(let success):
                iconId = success.id
            case .failure(_):
                iconId = ""
            }
        }
        
        return await req(method: .patch, route: "/channels/\(id)", parameters: ChannelEditPayload(name: name,
                                                                                                  description: description,
                                                                                                  icon: iconId,
                                                                                                  nsfw: nsfw,
                                                                                                  owner: owner,
                                                                                                  remove: remove))
    }
    
    func setDefaultPermission(target: String, permissions: Permissions)  async -> Result<Channel, RevoltError> {
        return await req(method: .put, route: "/channels/\(target)/permissions/default",
                         parameters: SetDefaultPermissionPayload(permissions: permissions))
    }
    
    func setChannelRolePermissions(target: String, role: String, permissions: Overwrite) async -> Result<Channel, RevoltError> {
        await req(method: .put, route: "/channels/\(target)/permissions/\(role)", parameters: ["permissions": ["allow": permissions.a, "deny": permissions.d]])
    }
    
    
    func fetchServerMembers(target: String, excludeOffline: Bool = false) async -> Result<MembersWithUsers, RevoltError> {
        return await req(method: .get,route: "/servers/\(target)/members?exclude_offline=\(excludeOffline)")
    }
    
    func deleteServer(target : String, leaveSilently : Bool = false) async -> Result<EmptyResponse, RevoltError> {
        return await req(method: .delete, route: "/servers/\(target)?leave_silently=\(leaveSilently)")
    }
    
    func deleteChannel(target : String, leaveSilently : Bool = false) async -> Result<EmptyResponse, RevoltError> {
        return await req(method: .delete, route: "/channels/\(target)?leave_silently=\(leaveSilently)")
    }
    
    func editMember(server: String, memberId: String, edits: EditMember) async -> Result<Member, RevoltError> {
        await req(method: .patch, route: "/servers/\(server)/members/\(memberId)", parameters: edits)
    }
    
    func kickMember(server : String, memberId: String) async -> Result<EmptyResponse, RevoltError>{
        await req(method: .delete, route: "/servers/\(server)/members/\(memberId)")
    }
    
    func createChannel(server : String, createChannel : CreateChannel) async -> Result<Channel, RevoltError>{
        await req(method: .post, route: "/servers/\(server)/channels", parameters: createChannel)
    }
    
    func createServer(createServer : CreateServer) async ->   Result<ServerChannel, RevoltError>{
        await req(method: .post, route: "/servers/create", parameters: createServer)
    }
    
}
