//
//  OEXAuthentication.m
//  edXVideoLocker
//
//  Created by Jotiram Bhagat on 25/06/14.
//  Copyright (c) 2014 edX. All rights reserved.
//

#import "OEXAuthentication.h"

#import "NSDictionary+OEXEncoding.h"

#import "OEXAppDelegate.h"
#import "OEXConfig.h"
#import "OEXFBSocial.h"
#import "OEXGoogleSocial.h"
#import "OEXInterface.h"
#import "OEXNetworkConstants.h"
#import "OEXUserDetails.h"

NSString * const authTokenResponse=@"authTokenResponse";
NSString * const oauthTokenKey = @"oauth_token";
NSString * const authTokenType =@"token_type";
NSString * const loggedInUser  =@"loginUserDetails";


NSString * const facebook_login_endpoint=@"facebook";
NSString * const google_login_endpoint=@"google-oauth2";


typedef void(^OEXSocialLoginCompletionHandler)(NSString *accessToken ,NSError *error);

@implementation OEXAuthentication


+(void)requestTokenWithUser:(NSString * )username password:(NSString * )password CompletionHandler:(RequestTokenCompletionHandler)completionBlock

{
    NSString *body = [self plainTextAuthorizationHeaderForUserName:username password:password];
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@%@", [OEXConfig sharedConfig].apiHostURL, AUTHORIZATION_URL]]];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        
        if (!error) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse*) response;
            if (httpResp.statusCode == 200) {
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSError *error;
                    
                    NSDictionary *dictionary =[NSJSONSerialization  JSONObjectWithData:data options:kNilOptions error:&error];
                    // save the REQUEST token and secret to use for normal api calls
                    [[NSUserDefaults standardUserDefaults] setObject:dictionary[@"access_token"] forKey:oauthTokenKey];
                    [[NSUserDefaults standardUserDefaults] setObject:dictionary forKey:authTokenResponse];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                    OEXAuthentication *edxAuth=[[OEXAuthentication alloc] init];
                    
                    [edxAuth getUserDetailsWithCompletionHandler:^(NSData *userdata, NSURLResponse *userresponse, NSError *usererror) {
                        if (!usererror) {
                            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse*) response;
                            if (httpResp.statusCode == 200) {
                                
                                NSError *error;
                                
                                NSDictionary *dictionary =[NSJSONSerialization  JSONObjectWithData:userdata options:kNilOptions error:&error];
                                [[NSUserDefaults standardUserDefaults] setObject:dictionary forKey:loggedInUser];
                                [[NSUserDefaults standardUserDefaults] synchronize];
                            }
                        }
                        completionBlock(userdata,userresponse,usererror);
                    }];
                });
            }
            else{
                completionBlock(data,response,error);
            }
        }else{
            
            completionBlock(data,response,error);
        }
        
    }]resume];
    
}

+(void)resetPasswordWithEmailId:(NSString *)email CSRFToken:(NSString *)token completionHandler:(RequestTokenCompletionHandler)completionBlock{
    
    NSString* string = [@{@"email" : email} oex_stringByUsingFormEncoding];
    NSData *postData = [string dataUsingEncoding:NSUTF8StringEncoding];
    
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@%@", [OEXConfig sharedConfig].apiHostURL, URL_RESET_PASSWORD]]];
    
    [request addValue:token forHTTPHeaderField:@"Cookie"];
    
    NSArray *parse = [token componentsSeparatedByString:@"="];
    
    [request addValue:[parse objectAtIndex:1] forHTTPHeaderField:@"X-CSRFToken"];
    
    [request addValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request addValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setHTTPMethod:@"POST"];
    
    [request setHTTPBody:postData];
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];
    
    
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            completionBlock(data,response,error);
            
        });
        
    }]resume];
}

+(NSString*)plainTextAuthorizationHeaderForUserName:(NSString*)userName password:(NSString*)password {
    NSString* clientID = [[OEXConfig sharedConfig] oauthClientID];
    NSString* clientSecret = [[OEXConfig sharedConfig] oauthClientSecret];

    return [@{
             @"client_id" : clientID,
             @"client_secret" : clientSecret,
             @"grant_type" : @"password",
             @"username" : userName,
             @"password" : password
             } oex_stringByUsingFormEncoding];
}

-(void)getUserDetailsWithCompletionHandler:(RequestTokenCompletionHandler)completionBlock{
    
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
    NSURLSessionConfiguration *config=[NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session =[NSURLSession sessionWithConfiguration:config
                                                         delegate:self
                                                    delegateQueue:nil];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@%@", [OEXConfig sharedConfig].apiHostURL, URL_GET_USER_INFO]]];
    NSString *authValue = [NSString stringWithFormat:@"%@",[OEXAuthentication authHeaderForApiAccess]];
    [request setValue:authValue forHTTPHeaderField:@"Authorization"];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
        if (!error) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode == 200)
            {
                completionBlock(data,response,error);
            }
        }
    }];
    [task resume];
    
}

+(NSString *)authHeaderForApiAccess{
    
    NSUserDefaults *userDefaults=[NSUserDefaults standardUserDefaults];
    NSString  *token=[userDefaults objectForKey:oauthTokenKey];
    NSDictionary *dict=[userDefaults objectForKey:authTokenResponse];
    
    if(token && dict){
        NSString *header = [NSString stringWithFormat:@"%@ %@", [dict objectForKey:authTokenType],token];
        return header;
        
    }else if(token){
        NSString *header = [NSString stringWithFormat:@"%@",token];
        return header;
    }
        
        return nil ;
    
}


- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)redirectResponse
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler{
    
    NSMutableURLRequest *mutablerequest = [request mutableCopy];
    NSString *authValue = [NSString stringWithFormat:@"%@",[OEXAuthentication authHeaderForApiAccess]];
    [mutablerequest setValue:authValue forHTTPHeaderField:@"Authorization"];
    
    completionHandler([mutablerequest copy]);
    
}

+(void)clearUserSessoin{
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if([OEXAuthentication getLoggedInUser])
        {
            ELog(@"clearUserSessoin -1");
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:loggedInUser];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [FBSession.activeSession closeAndClearTokenInformation];
            [[OEXGoogleSocial sharedInstance] logout];
        }
        ELog(@"clearUserSessoin -2");
    });
    
}

+(BOOL)isUserLoggedIn{
    NSDictionary *userDict=[[NSUserDefaults standardUserDefaults] objectForKey:loggedInUser];
    if(userDict!=nil){
        return YES ;
    }
    return NO;
}

+(OEXUserDetails *)getLoggedInUser
{
    /*
     "course_enrollments" = "http://mobile.m.sandbox.edx.org/public_api/users/staff/course_enrollments/";
     email = "staff@example.com";
     id = 4;
     name = staff;
     url = "http://mobile.m.sandbox.edx.org/public_api/users/staff";
     username = staff;
     */
    
    NSDictionary *userDict=[[NSUserDefaults standardUserDefaults] objectForKey:loggedInUser];
    
    if(userDict){
        
        OEXUserDetails *user=[[OEXUserDetails alloc] init];
        user.name=[userDict objectForKey:@"name"];
        user.username=[userDict objectForKey:@"username"];
        user.email=[userDict objectForKey:@"email"];
        user.User_id=[[userDict objectForKey:@"id"] longValue];
        user.course_enrollments=[userDict objectForKey:@"course_enrollments"];
        user.url=[userDict objectForKey:@"url"];
        
        //NSLog(@"getLoggedInUser -1");
        return user;
    }
    //NSLog(@"getLoggedInUser -2");
    return nil ;
    
    
}

+(void)saveUserCredentials{
    
}


#pragma mark Social Login Mrthods

+(void)socialLoginWith:(OEXSocialLoginType)loginType completionHandler:(RequestTokenCompletionHandler)handler{
    switch (loginType) {
        case OEXFacebookLogin: {
            [OEXAuthentication loginWithFacebook:^(NSString *accessToken,NSError *error) {
                if(accessToken){
                    [OEXAuthentication authenticateWithAccessToken:accessToken loginType:OEXFacebookLogin completionHandler:handler];
                }else{
                    handler(nil,nil,error);
                }
            }];
            break;
        }
        case OEXGoogleLogin: {
            [OEXAuthentication loginWithGoogle:^(NSString *accessToken , NSError *error) {
                if(accessToken){
                    [OEXAuthentication authenticateWithAccessToken:accessToken loginType:OEXGoogleLogin completionHandler:handler];
                }else{
                    handler(nil,nil,error);
                }
             }];
            break;
        }
            
        default:{
            handler(nil,nil,nil);
            break;

        }
            
            
    }
}


+(void)authenticateWithAccessToken:(NSString *)token  loginType:(OEXSocialLoginType)loginType completionHandler:(void(^)(NSData *userdata, NSURLResponse *userresponse, NSError *usererror))handler{
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
    NSString *endpath;
    if(loginType == OEXFacebookLogin) {
        endpath=facebook_login_endpoint;
    } else {
        endpath=google_login_endpoint;
    }
    /// Create  request object to authenticate accesstoken
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@/%@/", [OEXConfig sharedConfig].apiHostURL,URL_SOCIAL_LOGIN, endpath]]];
    NSString* string = [@{@"access_token" : token} oex_stringByUsingFormEncoding];
    NSData *postData = [string dataUsingEncoding:NSUTF8StringEncoding];
    [request addValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request addValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:postData];
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse*) response;
            if (httpResp.statusCode == 204) {
                ///Save Access token
                [self saveAccessToken:token];

                [OEXAuthentication handleSocialLoginSuccessFull:handler];
                return ;
            }
            else if(httpResp.statusCode==401)
            {
                [[OEXGoogleSocial sharedInstance]clearGoogleSession];
                error=[NSError errorWithDomain:@"Not valid user" code:401 userInfo:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObject:@"You are not associated with edx please sigun up from website"] forKeys:[NSArray arrayWithObject:@"failed"]]];
            }
            
        }
        handler(data,response,error);
        
    }]resume];
    
}


+(void)handleSocialLoginSuccessFull:(RequestTokenCompletionHandler )completionHandeler{
  
    OEXAuthentication *edxAuth=[[OEXAuthentication alloc] init];
    [edxAuth getUserDetailsWithCompletionHandler:^(NSData *userdata, NSURLResponse *userresponse, NSError *usererror) {
         if (!usererror) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse*) userresponse;
            if (httpResp.statusCode == 200) {
                NSDictionary *dictionary =[NSJSONSerialization  JSONObjectWithData:userdata options:kNilOptions error:nil];
                [[NSUserDefaults standardUserDefaults] setObject:dictionary forKey:loggedInUser];
                [[NSUserDefaults standardUserDefaults] synchronize];
            }
         }
         completionHandeler(userdata,userresponse,usererror);
     }];
  
}

+(void)loginWithGoogle:(OEXSocialLoginCompletionHandler)handler{
    [[OEXGoogleSocial sharedInstance] googleLogin:^(NSString *accessToken , NSError *error){
        handler(accessToken,error);
    }];
}

+(void)loginWithFacebook:(OEXSocialLoginCompletionHandler)handler{
    
    [[OEXFBSocial sharedInstance]login:^(NSString *sessionToken, FBSessionState status, NSError *error) {
        //[[FBSocial sharedInstance]logout];
        switch (status) {
            case FBSessionStateOpen:
                {
                  handler([FBSession.activeSession accessTokenData].accessToken,error);
                }
                break;
            case FBSessionStateClosed:{
               
               }
                break;
            case FBSessionStateClosedLoginFailed:
                handler(nil,error);
                break;
            default:
                break;
        }
    }];
}

+(void)saveAccessToken:(NSString *)token{
    if([[NSUserDefaults standardUserDefaults] objectForKey:authTokenResponse]){
        [[NSUserDefaults standardUserDefaults]removeObjectForKey:authTokenResponse];
    }
    [[NSUserDefaults standardUserDefaults] setObject:token forKey:oauthTokenKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
}

@end
