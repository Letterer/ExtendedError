import Vapor
import Foundation

/// Captures all errors and transforms them into an internal server error HTTP response.
public final class CustomErrorMiddleware: Middleware {

    /// Structure of `CustomErrorMiddleware` default response.
    internal struct ErrorResponse: Codable {
        /// Always `true` to indicate this is a non-typical JSON response.
        var error: Bool

        /// The reason for the error.
        var reason: String

        /// The code of the reason.
        var code: String?
        
        /// List with validation failures.
        var failures: [ValidationFailure]?
    }
    
    /// Structure for validation error failures.
    internal struct ValidationFailure: Codable {
        /// Field with validation error.
        var field: String
        
        /// Validation message.
        var failure: String?
    }
    
    public init() {
    }
    
    /// See `Middleware`.
    public func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        let response = next.respond(to: request)
        return response.flatMapError { error in
            return self.body(request: request, error: error)
        }
    }

    /// Error-handling closure.
    private func body(request: Request, error: Error) -> EventLoopFuture<Response> {

        let logger = request.application.logger
        
        // log the error
        logger.report(error: error)

        // variables to determine
        let status: HTTPResponseStatus
        let reason: String
        let headers: HTTPHeaders
        let code: String?
        var failures: [ValidationFailure]?

        // inspect the error type
        switch error {
        case let terminate as TerminateError:
            reason = terminate.reason
            status = terminate.status
            headers = terminate.headers
            code = terminate.code
        case let validation as Vapor.ValidationsError:
            reason = "Validation errors occurs."
            
            failures = []
            for failure in validation.failures {
                failures?.append(ValidationFailure(field: failure.key.stringValue, failure: failure.result.failureDescription))
            }
            
            status = .badRequest
            headers = [:]
            code = "validationError"
        case let abort as AbortError:
            reason = abort.reason
            status = abort.status
            headers = abort.headers
            code = "abortError"
        default:
            reason = "Something went wrong."
            status = .internalServerError
            headers = [:]
            code = "internalApplicationError"
        }

        // Attempt to serialize the error to json.
        do {
            let errorResponse = ErrorResponse(error: true, reason: reason, code: code, failures: failures)
            let body = try Response.Body(data: JSONEncoder().encode(errorResponse))
            let response = Response(status: status, headers: headers, body: body)
            response.headers.replaceOrAdd(name: .contentType, value: "application/json; charset=utf-8")

            return request.eventLoop.makeSucceededFuture(response)
        } catch {
            let body = Response.Body(string: "Oops: \(error)")
            let response = Response(status: status, headers: headers, body: body)
            response.headers.replaceOrAdd(name: .contentType, value: "text/plain; charset=utf-8")
            
            return request.eventLoop.makeSucceededFuture(response)
        }
    }
}
