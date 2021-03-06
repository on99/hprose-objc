/**********************************************************\
 |                                                          |
 |                          hprose                          |
 |                                                          |
 | Official WebSite: http://www.hprose.com/                 |
 |                   http://www.hprose.org/                 |
 |                                                          |
 \**********************************************************/
/**********************************************************\
 *                                                        *
 * HproseHttpClient.m                                     *
 *                                                        *
 * hprose http client for Objective-C.                    *
 *                                                        *
 * LastModified: Feb 6, 2016                              *
 * Author: Ma Bingyao <andot@hprose.com>                  *
 *                                                        *
 \**********************************************************/

#import "HproseException.h"
#import "HproseHttpClient.h"

@interface AsyncInvokeContext: NSObject<NSURLConnectionDelegate> {
@private
    NSMutableData *_buffer;
    BOOL _hasError;
    void (^_callback)(NSData *);
    void (^_errorHandler)(NSException *);
    HproseHttpClient * _client;
}

- (void)connection:(NSURLConnection *)theConnection didReceiveResponse:(NSURLResponse *)response;
- (void)connection:(NSURLConnection *)theConnection didReceiveData:(NSData *)data;
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error;
- (void)connectionDidFinishLoading:(NSURLConnection *)theConnection;
@end

@implementation AsyncInvokeContext

- (id) init:(HproseHttpClient *)client callback:(void (^)(NSData *))callback errorHandler:(void (^)(NSException *)) errorHandler {
    if (self = [super init]) {
        _buffer = [NSMutableData data];
        _client = client;
        _callback = callback;
        _errorHandler = errorHandler;
        _hasError = NO;
    }
    return self;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
#pragma unused(connection)
    NSHTTPURLResponse * httpResponse = (NSHTTPURLResponse *) response;
    if ([httpResponse statusCode] != 200) {
        _hasError = YES;
        _errorHandler([HproseException exceptionWithReason:
                       [NSString stringWithFormat:@"%d: %@",
                        (int)[httpResponse statusCode],
                        [NSHTTPURLResponse localizedStringForStatusCode:[httpResponse statusCode]]]]);
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
#pragma unused(connection)
    [_buffer appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
#pragma unused(connection)
    if (!_hasError) {
        _callback(_buffer);
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    _hasError = YES;
    _errorHandler([HproseException exceptionWithReason:[NSString stringWithFormat:@"%d: %@",
                                                        (int)[error code],
                                                        [error localizedDescription]]]);
    if ([[_client URLConnectionDelegate] respondsToSelector:@selector(connection:didFailWithError:)]) {
        [[_client URLConnectionDelegate] connection:connection didFailWithError:error];
    }
}

- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    if ([[_client URLConnectionDelegate] respondsToSelector:@selector(connection:willSendRequestForAuthenticationChallenge:)]) {
        [[_client URLConnectionDelegate] connection:connection willSendRequestForAuthenticationChallenge:challenge];
    }
}

#if !defined(__MAC_10_7) && !defined(__IPHONE_7_0) && !defined(__TVOS_9_0) && !defined(__WATCHOS_1_0)
- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
    if ([[_client URLConnectionDelegate] respondsToSelector:@selector(connection:canAuthenticateAgainstProtectionSpace:)]) {
        return [[_client URLConnectionDelegate] connection:connection canAuthenticateAgainstProtectionSpace:protectionSpace];
    }
    return [protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust] || [protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodClientCertificate];
}

- (void)connection:(NSURLConnection *)connection didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    if ([[_client URLConnectionDelegate] respondsToSelector:@selector(connection:didCancelAuthenticationChallenge:)]) {
        [[_client URLConnectionDelegate] connection:connection didCancelAuthenticationChallenge:challenge];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    if ([[_client URLConnectionDelegate] respondsToSelector:@selector(connection:didReceiveAuthenticationChallenge:)]) {
        [[_client URLConnectionDelegate] connection:connection didReceiveAuthenticationChallenge:challenge];
    }
    else {
        NSURLCredential *credential;
        if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
            credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        }
        else if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodClientCertificate]) {
            credential = nil;
        }
        if (credential != nil) {
            [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
        }
        else {
            [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
        }
    }
}
#endif

- (BOOL)connectionShouldUseCredentialStorage:(NSURLConnection *)connection {
    if ([[_client URLConnectionDelegate] respondsToSelector:@selector(connectionShouldUseCredentialStorage:)]) {
        return [[_client URLConnectionDelegate] connectionShouldUseCredentialStorage:connection];
    }
    return NO;
}

@end

@interface HproseHttpClient () <NSURLSessionDelegate>

@property (nonatomic, strong) NSURLSession *session;

@end

@implementation HproseHttpClient

- (id) init {
    if (self = [super init]) {
        [self setTimeout:30.0];
        [self setKeepAlive:YES];
        [self setKeepAliveTimeout:300];
        [self setURLConnectionDelegate:nil];
        [self setURLSessionDelegate:nil];
        _header = [NSMutableDictionary new];
    }
    return self;
}

- (NSURLSession *)session {
    if (!_session) {
        NSURLSessionConfiguration *conf = [NSURLSessionConfiguration defaultSessionConfiguration];
        _session = [NSURLSession sessionWithConfiguration:conf
                                                 delegate:self.URLSessionDelegate
                                            delegateQueue:[NSOperationQueue new]];
    }
    
    return _session;
}

@dynamic uri;

- (void) setUri:(NSString *)aUri {
    if ([super uri] != aUri) {
        [super setUri:aUri];
        url = [NSURL URLWithString:aUri];
    }
}

- (void) setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if (field != nil) {
        if (value != nil) {
            _header[field] = value;
        }
        else {
            [_header removeObjectForKey:field];
        }
    }
}

- (NSData *) sendAndReceive:(NSData *)data {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setTimeoutInterval:_timeout];
    for (id field in _header) {
        [request setValue:_header[field] forHTTPHeaderField:field];
    }
    if (_keepAlive) {
        [request setValue:@"keep-alive" forHTTPHeaderField:@"Connection"];
        [request setValue:[@(_keepAliveTimeout) stringValue] forHTTPHeaderField:@"Keep-Alive"];
    }
    else {
        [request setValue:@"close" forHTTPHeaderField:@"Connection"];
    }
    [request setValue:@"application/hprose" forHTTPHeaderField:@"Content-type"];
    [request setHTTPShouldHandleCookies:YES];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:data];
    
    __block NSHTTPURLResponse *response;
    __block NSError *error;
    __block NSData *ret;
#if !defined(__MAC_10_7) && !defined(__IPHONE_7_0) && !defined(__TVOS_9_0) && !defined(__WATCHOS_1_0)
    ret = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
#else
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable resp, NSError * _Nullable err) {
        response = (NSHTTPURLResponse *)resp;
        error = err;
        ret = data;
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
#endif
    
    NSInteger statusCode = [response statusCode];
    if (statusCode != 200 && statusCode != 0) {
        @throw [HproseException exceptionWithReason:
                [NSString stringWithFormat:@"%d: %@",
                 (int)statusCode,
                 [NSHTTPURLResponse localizedStringForStatusCode:statusCode]]];
    }
    if (ret == nil) {
        @throw [HproseException exceptionWithReason:[NSString stringWithFormat:@"%d: %@",
                                                     (int)[error code],
                                                     [error localizedDescription]]];
    }
    return ret;
}

- (oneway void) sendAsync:(NSData *)data
             receiveAsync:(void (^)(NSData *))receiveCallback
                    error:(void (^)(NSException *))errorCallback {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setTimeoutInterval:_timeout];
    for (id field in _header) {
        [request setValue:_header[field] forHTTPHeaderField:field];
    }
    if (_keepAlive) {
        [request setValue:@"keep-alive" forHTTPHeaderField:@"Connection"];
        [request setValue:[@(_keepAliveTimeout) stringValue] forHTTPHeaderField:@"Keep-Alive"];
    }
    else {
        [request setValue:@"close" forHTTPHeaderField:@"Connection"];
    }
    [request setValue:@"application/hprose" forHTTPHeaderField:@"Content-type"];
    [request setHTTPShouldHandleCookies:YES];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:data];
#if !defined(__MAC_10_7) && !defined(__IPHONE_7_0) && !defined(__TVOS_9_0) && !defined(__WATCHOS_1_0)
    AsyncInvokeContext *context = [[AsyncInvokeContext alloc] init:self callback:receiveCallback errorHandler:errorCallback];
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:request delegate:context startImmediately:NO];
    [connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    [connection start];
#else
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            NSException *e = [HproseException exceptionWithReason:[NSString stringWithFormat:@"%d: %@",
                                                                   (int)[error code],
                                                                   [error localizedDescription]]];
            errorCallback(e);
            return;
        }
        
        
        dispatch_async(dispatch_get_main_queue(), ^{
            receiveCallback(data);
        });
    }];
    [task resume];
#endif
}

@end