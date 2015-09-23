/*
 * Copyright 2008-2011, Torsten Curdt
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "FRFeedbackController.h"
#import "FRFeedbackReporter.h"
#import "FRUploader.h"
#import "FRApplication.h"
#import "FRSystemProfile.h"
#import "FRConstants.h"
#import "FRConsoleLog.h"

#ifdef __MAC_OS_X_VERSION_MAX_ALLOWED
#import "FRMacFeedbackWindowController.h"
#import "FRCommand.h"
#endif
#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
#import "FRiOSFeedbackTableViewController.h"
#endif

#import "NSMutableDictionary+Additions.h"

#import <SystemConfiguration/SystemConfiguration.h>


@interface FRFeedbackController ()

@property (nonatomic, strong)       FRUploader *uploader;
@property (nonatomic, strong)       NSArray *emailRequiredTypes;
@property (nonatomic, strong)       NSArray *emailStronglySuggestedTypes;

- (NSMutableDictionary *) parametersForFeedbackReport;
- (BOOL) shouldSend:(id)sender;
- (BOOL) shouldAttemptSendForUnreachableHost:(NSString *)host;

@end


#ifdef __MAC_OS_X_VERSION_MAX_ALLOWED
@interface FRMacFeedbackController : FRFeedbackController <FRUploaderDelegate>

@property (nonatomic, strong)       FRMacFeedbackWindowController *windowController;

@end
#endif


#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
@interface FRiOSFeedbackController : FRFeedbackController <FRUploaderDelegate>

@property (nonatomic, strong)       FRiOSFeedbackTableViewController *controller;

@end
#endif


@implementation FRFeedbackController

+ (instancetype) alloc
{
    if ( [self class] == [FRFeedbackController class] ) {
#ifdef __MAC_OS_X_VERSION_MAX_ALLOWED
        return [FRMacFeedbackController alloc];
#else
        return [FRiOSFeedbackController alloc];
#endif
    }
    else {
        return [super alloc];
    }
}

- (instancetype) init
{
    self = [super init];
    if ( self ) {
        self.emailRequiredTypes = [NSArray arrayWithObject:FR_SUPPORT];
        self.emailStronglySuggestedTypes = [NSArray arrayWithObjects:FR_FEEDBACK, FR_CRASH, nil];
    }
    return self;
}


#pragma mark Accessors

- (void) setTitle:(NSString *)title
{
}

- (void) setHeading:(NSString *)message
{
}

- (void) setSubheading:(NSString *)informativeText
{
}

- (void) setMessage:(NSString *)message
{
}

- (void) setCrash:(NSString *)crash
{
}

- (void) setException:(NSString *)exception
{
}


#pragma mark information gathering

- (NSString *) consoleLog
{
    NSNumber *hours = [[[NSBundle mainBundle] infoDictionary] valueForKey:PLIST_KEY_LOGHOURS];

    NSInteger h = 24;

    if (hours != nil) {
        h = [hours integerValue];
    }
    
    NSDate *since = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitHour value:-h toDate:[NSDate date] options:0];

    NSNumber *maximumSize = [[[NSBundle mainBundle] infoDictionary] valueForKey:PLIST_KEY_MAXCONSOLELOGSIZE];

    return [FRConsoleLog logSince:since maxSize:maximumSize];
}


- (NSArray *) systemProfile
{
    static NSArray *systemProfile = nil;
    
    if (systemProfile == nil) {
        systemProfile = [FRSystemProfile discover];
    }
    
    return systemProfile;
}

- (NSString *) systemProfileAsString
{
    NSMutableString *string = [NSMutableString string];
    NSArray *dicts = [self systemProfile];
    NSUInteger i = [dicts count];
    while(i--) {
        NSDictionary *dict = [dicts objectAtIndex:i];
        [string appendFormat:@"%@ = %@\n", [dict objectForKey:@"key"], [dict objectForKey:@"value"]];
    }
    return string;
}

- (NSString *) preferences
{
    NSMutableDictionary *preferences = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:[FRApplication applicationIdentifier]] mutableCopy];
    
    if (preferences == nil) {
        return @"";
    }
    
    [preferences removeObjectForKey:DEFAULTS_KEY_SENDEREMAIL];
    
    if ([self.delegate respondsToSelector:@selector(anonymizePreferencesForFeedbackReport:)]) {
        preferences = [self.delegate anonymizePreferencesForFeedbackReport:preferences];
    }
    
    return [NSString stringWithFormat:@"%@", preferences];
}


#pragma mark UI Actions

- (BOOL) shouldSend:(id)sender
{
    return YES;
}

- (BOOL) shouldAttemptSendForUnreachableHost:(NSString *)host
{
    return NO;
}

- (NSMutableDictionary *) parametersForFeedbackReport
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    [dict setValidString:self.type
                  forKey:POST_KEY_TYPE];
    
    [dict setValidString:[FRApplication applicationLongVersion]
                  forKey:POST_KEY_VERSION_LONG];
    
    [dict setValidString:[FRApplication applicationShortVersion]
                  forKey:POST_KEY_VERSION_SHORT];
    
    [dict setValidString:[FRApplication applicationBundleVersion]
                  forKey:POST_KEY_VERSION_BUNDLE];
    
    [dict setValidString:[FRApplication applicationVersion]
                  forKey:POST_KEY_VERSION];
    
    return dict;
}


#pragma mark FRUploaderDelegate

- (void) uploaderStarted:(FRUploader *)uploader
{
    // NSLog(@"Upload started");
}

- (void) uploaderFailed:(FRUploader *)uploader withError:(NSError *)error
{
    NSLog(@"Upload failed: %@", error);
}

- (void) uploaderFinished:(FRUploader *)uploader
{
    // NSLog(@"Upload finished");
}


#pragma mark other

- (void) cancelUpload
{
    [self.uploader cancel];
    self.uploader = nil;
}

- (void) send:(id)sender
{
    if (self.uploader != nil) {
        NSLog(@"Still uploading");
        return;
    }
    
    if ( [self shouldSend:sender] == NO )
        return;
    
    NSString *target = [[FRApplication feedbackURL] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ;
    
    if ([[[FRFeedbackReporter sharedReporter] delegate] respondsToSelector:@selector(targetUrlForFeedbackReport)]) {
        target = [[[FRFeedbackReporter sharedReporter] delegate] targetUrlForFeedbackReport];
    }
    
    if (target == nil) {
        NSLog(@"You are missing the %@ key in your Info.plist!", PLIST_KEY_TARGETURL);
        return;
    }
    
    NSURL *url = [NSURL URLWithString:target];
    
    NSString *host = [url host];
    const char *hostname = [host UTF8String];
    
    SCNetworkConnectionFlags reachabilityFlags = 0;
    Boolean reachabilityResult = FALSE;
    
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, hostname);
    if (reachability) {
        reachabilityResult = SCNetworkReachabilityGetFlags(reachability, &reachabilityFlags);
        CFRelease(reachability);
    }
    
    // Prevent premature release (UTF8String returns an inner pointer).
    [host self];
    
    BOOL reachable = reachabilityResult
        &&  (reachabilityFlags & kSCNetworkFlagsReachable)
        && !(reachabilityFlags & kSCNetworkFlagsConnectionRequired)
        && !(reachabilityFlags & kSCNetworkFlagsConnectionAutomatic)
        && !(reachabilityFlags & kSCNetworkFlagsInterventionRequired);
    
    if (!reachable) {
        if ( [self shouldAttemptSendForUnreachableHost:host] == NO ) {
            return;
        }
    }
    
    self.uploader = [[FRUploader alloc] initWithTarget:target delegate:self];
    
    NSMutableDictionary *dict = [self parametersForFeedbackReport];
    
    NSLog(@"Sending feedback to %@", target);
    
    [self.uploader postAndNotify:dict];
}

- (void) show
{
}

- (void) close
{
}

- (void) reset
{
}

- (BOOL) isShown
{
    return NO;
}

@end


#ifdef __MAC_OS_X_VERSION_MAX_ALLOWED
@implementation FRMacFeedbackController

#pragma mark Accessors

- (FRMacFeedbackWindowController *) windowController
{
    if ( !_windowController ) {
        _windowController = [[FRMacFeedbackWindowController alloc] initWithWindowNibName:@"FRMacFeedbackWindowController"];
        _windowController.feedbackController = self;
    }
    return _windowController;
}

- (void) setTitle:(NSString *)title
{
    [super setTitle:title];
    [[self.windowController window] setTitle:title];
}

- (void) setHeading:(NSString *)message
{
    [super setHeading:message];
    [self.windowController.headingField setStringValue:message];
}

- (void) setSubheading:(NSString *)informativeText
{
    [super setSubheading:informativeText];
    [self.windowController.subheadingField setStringValue:informativeText];
}

- (void) setMessage:(NSString *)message
{
    [super setMessage:message];
    [self.windowController.messageView setString:message];
}

- (void) setCrash:(NSString *)crash
{
    [super setCrash:crash];
    [self.windowController.crashesView setString:crash];
}

- (void) setException:(NSString *)exception
{
    [super setException:exception];
    [self.windowController.exceptionView setString:exception];
}

- (void) setType:(NSString *)type
{
    [super setType:type];
    self.windowController.type = type;
}


#pragma mark UI Actions

- (BOOL) shouldSend:(id)sender
{
    // Check that email is present
    if ([self.windowController.emailBox stringValue] == nil || [[self.windowController.emailBox stringValue] isEqualToString:@""] || [[self.windowController.emailBox stringValue] isEqualToString:FRLocalizedString(@"anonymous", nil)]) {
        for (NSString *aType in self.emailRequiredTypes) {
            if ([aType isEqualToString:self.type]) {
                [[NSAlert alertWithMessageText:@"Email required" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"You must enter an email address so that we can respond to you."] runModal];
                return NO;
            }
        }
        for (NSString *aType in self.emailStronglySuggestedTypes) {
            if ([aType isEqualToString:self.type]) {
                NSInteger buttonPressed = [[NSAlert alertWithMessageText:@"Email missing" defaultButton:@"OK" alternateButton:@"Continue anyway" otherButton:nil informativeTextWithFormat:@"Email is missing. Without an email address, we cannot respond to you. Go back and enter one?"] runModal];
                if (buttonPressed == NSAlertDefaultReturn)
                    return NO;
                break;
            }
        }
    }
    return YES;
}

- (BOOL) shouldAttemptSendForUnreachableHost:(NSString *)host
{
    NSInteger alertResult = [[NSAlert alertWithMessageText:FRLocalizedString(@"Feedback Host Not Reachable", nil)
                                             defaultButton:FRLocalizedString(@"Proceed Anyway", nil)
                                           alternateButton:FRLocalizedString(@"Cancel", nil)
                                               otherButton:nil
                                 informativeTextWithFormat:FRLocalizedString(@"You may not be able to send feedback because %@ isn't reachable.", nil), host
                              ] runModal];
    
    if (alertResult != NSAlertDefaultReturn) {
        return NO;
    }
    
    return YES;
}

- (NSMutableDictionary *) parametersForFeedbackReport
{
    NSMutableDictionary *dict = [super parametersForFeedbackReport];
    
    [dict setValidString:[self.windowController.emailBox stringValue]
                  forKey:POST_KEY_EMAIL];
    
    [dict setValidString:[self.windowController.messageView string]
                  forKey:POST_KEY_MESSAGE];
    
    if ([self.windowController.sendDetailsCheckbox state] == NSOnState) {
        if ([self.delegate respondsToSelector:@selector(customParametersForFeedbackReport)]) {
            [dict addEntriesFromDictionary:[self.delegate customParametersForFeedbackReport]];
        }
        
        [dict setValidString:[self systemProfileAsString]
                      forKey:POST_KEY_SYSTEM];
        
        if ([self.windowController.includeConsoleCheckbox state] == NSOnState)
            [dict setValidString:[self.windowController.consoleView string]
                          forKey:POST_KEY_CONSOLE];
        
        [dict setValidString:[self.windowController.crashesView string]
                      forKey:POST_KEY_CRASHES];
        
        [dict setValidString:[self.windowController.scriptView string]
                      forKey:POST_KEY_SHELL];
        
        [dict setValidString:[self.windowController.preferencesView string]
                      forKey:POST_KEY_PREFERENCES];
        
        [dict setValidString:[self.windowController.exceptionView string]
                      forKey:POST_KEY_EXCEPTION];
        
        if (self.windowController.documentList) {
            NSDictionary *documents = [self.windowController.documentList documentsToUpload];
            if (documents && [documents count] > 0)
                [dict setObject:documents forKey:POST_KEY_DOCUMENTS];
        }
    }
    
    return dict;
}

#pragma mark FRUploaderDelegate

- (void) uploaderStarted:(FRUploader *)uploader
{
    [super uploaderStarted:uploader];
    
    self.windowController.uploading = YES;
}

- (void) uploaderFailed:(FRUploader *)uploader withError:(NSError *)error
{
    [super uploaderFailed:uploader withError:error];
    
    self.uploader = nil;
    
    self.windowController.uploading = NO;
    
    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:FRLocalizedString(@"OK", nil)];
    [alert setMessageText:FRLocalizedString(@"Sorry, failed to submit your feedback to the server.", nil)];
    [alert setInformativeText:[NSString stringWithFormat:FRLocalizedString(@"Error: %@", nil), [error localizedDescription]]];
    [alert setAlertStyle:NSWarningAlertStyle];
    [alert runModal];
    
    [self close];
}

- (void) uploaderFinished:(FRUploader *)uploader
{
    [super uploaderFinished:uploader];
    
    NSString *response = [self.uploader response];
    
    self.uploader = nil;
    
    self.windowController.uploading = NO;
    
    NSArray *lines = [response componentsSeparatedByString:@"\n"];
    NSUInteger i = [lines count];
    while(i--) {
        NSString *line = [lines objectAtIndex:i];
        
        if ([line length] == 0) {
            continue;
        }
        
        if (![line hasPrefix:@"OK "]) {
            
            NSLog (@"Failed to submit to server: %@", response);
            
            NSAlert *alert = [[NSAlert alloc] init];
            [alert addButtonWithTitle:FRLocalizedString(@"OK", nil)];
            [alert setMessageText:FRLocalizedString(@"Sorry, failed to submit your feedback to the server.", nil)];
            [alert setInformativeText:[NSString stringWithFormat:FRLocalizedString(@"Error: %@", nil), line]];
            [alert setAlertStyle:NSWarningAlertStyle];
            [alert runModal];
            
            return;
        }
    }
    
    [[NSUserDefaults standardUserDefaults] setValue:[NSDate date]
                                             forKey:DEFAULTS_KEY_LASTSUBMISSIONDATE];
    
    [[NSUserDefaults standardUserDefaults] setObject:[self.windowController.emailBox stringValue]
                                              forKey:DEFAULTS_KEY_SENDEREMAIL];
    
    [self close];
}

- (void) show
{
    [super show];
    [self.windowController show];
}

- (void) close
{
    [super close];
    [self.windowController close];
    _windowController = nil;
}

- (void) reset
{
    BOOL emailRequired = ( [self.emailRequiredTypes containsObject:self.type] || [self.emailStronglySuggestedTypes containsObject:self.type] );
    [self.windowController resetWithEmailRequired:emailRequired];
}

- (BOOL) isShown
{
    return [[self.windowController window] isVisible];
}

@end
#endif


#ifdef __IPHONE_OS_VERSION_MAX_ALLOWED
@implementation FRiOSFeedbackController

#pragma mark Accessors

- (FRiOSFeedbackTableViewController *) controller
{
    if ( !_controller ) {
        _controller = [[FRiOSFeedbackTableViewController alloc] initWithNibName:@"FRiOSFeedbackTableViewController" bundle:[NSBundle bundleForClass:[self class]]];
        
        _controller.feedbackController = self;
    }
    return _controller;
}

- (void) setTitle:(NSString *)title
{
    [super setTitle:title];
    self.controller.titleText = title;
}

- (void) setHeading:(NSString *)message
{
    [super setHeading:message];
    self.controller.headingText = message;
}

- (void) setSubheading:(NSString *)informativeText
{
    [super setSubheading:informativeText];
    self.controller.subheadingText = informativeText;
}

- (void) setMessage:(NSString *)message
{
    [super setMessage:message];
    self.controller.messageViewText = message;
}

- (void) setCrash:(NSString *)crash
{
    [super setCrash:crash];
    self.controller.crashesViewText = crash;
}

- (void) setException:(NSString *)exception
{
    [super setException:exception];
    self.controller.exceptionViewText = exception;
}

- (void) setType:(NSString *)type
{
    [super setType:type];
    self.controller.type = type;
}


#pragma mark UI Actions

- (BOOL) shouldSend:(id)sender
{
    // Check that email is present
    if (self.controller.emailBoxText == nil || [self.controller.emailBoxText isEqualToString:@""] || [self.controller.emailBoxText isEqualToString:FRLocalizedString(@"anonymous", nil)]) {
        for (NSString *aType in self.emailRequiredTypes) {
            if ([aType isEqualToString:self.type]) {
//                [[NSAlert alertWithMessageText:@"Email required" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"You must enter an email address so that we can respond to you."] runModal];
                return NO;
            }
        }
        for (NSString *aType in self.emailStronglySuggestedTypes) {
            if ([aType isEqualToString:self.type]) {
//                NSInteger buttonPressed = [[NSAlert alertWithMessageText:@"Email missing" defaultButton:@"OK" alternateButton:@"Continue anyway" otherButton:nil informativeTextWithFormat:@"Email is missing. Without an email address, we cannot respond to you. Go back and enter one?"] runModal];
//                if (buttonPressed == NSAlertDefaultReturn)
//                    return NO;
                break;
            }
        }
    }
    return YES;
}

- (BOOL) shouldAttemptSendForUnreachableHost:(NSString *)host
{
//    NSInteger alertResult = [[NSAlert alertWithMessageText:FRLocalizedString(@"Feedback Host Not Reachable", nil)
//                                             defaultButton:FRLocalizedString(@"Proceed Anyway", nil)
//                                           alternateButton:FRLocalizedString(@"Cancel", nil)
//                                               otherButton:nil
//                                 informativeTextWithFormat:FRLocalizedString(@"You may not be able to send feedback because %@ isn't reachable.", nil), host
//                              ] runModal];
//    
//    if (alertResult != NSAlertDefaultReturn) {
//        return NO;
//    }
//    
    return YES;
}

- (NSMutableDictionary *) parametersForFeedbackReport
{
    NSMutableDictionary *dict = [super parametersForFeedbackReport];
    
    [dict setValidString:self.controller.emailBoxText
                  forKey:POST_KEY_EMAIL];
    
    [dict setValidString:self.controller.messageViewText
                  forKey:POST_KEY_MESSAGE];
    
    if ( self.controller.sendDetails ) {
        if ([self.delegate respondsToSelector:@selector(customParametersForFeedbackReport)]) {
            [dict addEntriesFromDictionary:[self.delegate customParametersForFeedbackReport]];
        }
        
        [dict setValidString:[self systemProfileAsString]
                      forKey:POST_KEY_SYSTEM];
        
        if ( self.controller.includeConsole )
            [dict setValidString:self.controller.consoleViewText
                          forKey:POST_KEY_CONSOLE];
        
        [dict setValidString:self.controller.crashesViewText
                      forKey:POST_KEY_CRASHES];
        
        [dict setValidString:self.controller.scriptViewText
                      forKey:POST_KEY_SHELL];
        
        [dict setValidString:self.controller.preferencesViewText
                      forKey:POST_KEY_PREFERENCES];
        
        [dict setValidString:self.controller.exceptionViewText
                      forKey:POST_KEY_EXCEPTION];
        
//        if ( self.controller.documentList ) {
//            NSDictionary *documents = [self.controller.documentList documentsToUpload];
//            if (documents && [documents count] > 0)
//                [dict setObject:documents forKey:POST_KEY_DOCUMENTS];
//        }
    }
    
    return dict;
}

#pragma mark FRUploaderDelegate

- (void) uploaderStarted:(FRUploader *)uploader
{
    [super uploaderStarted:uploader];
    
    self.controller.uploading = YES;
}

- (void) uploaderFailed:(FRUploader *)uploader withError:(NSError *)error
{
    [super uploaderFailed:uploader withError:error];
    
    self.uploader = nil;
    
    self.controller.uploading = NO;
    
//    NSAlert *alert = [[NSAlert alloc] init];
//    [alert addButtonWithTitle:FRLocalizedString(@"OK", nil)];
//    [alert setMessageText:FRLocalizedString(@"Sorry, failed to submit your feedback to the server.", nil)];
//    [alert setInformativeText:[NSString stringWithFormat:FRLocalizedString(@"Error: %@", nil), [error localizedDescription]]];
//    [alert setAlertStyle:NSWarningAlertStyle];
//    [alert runModal];
    
    [self close];
}

- (void) uploaderFinished:(FRUploader *)uploader
{
    [super uploaderFinished:uploader];
    
    NSString *response = [self.uploader response];
    
    self.uploader = nil;
    
    self.controller.uploading = NO;
    
    NSArray *lines = [response componentsSeparatedByString:@"\n"];
    NSUInteger i = [lines count];
    while(i--) {
        NSString *line = [lines objectAtIndex:i];
        
        if ([line length] == 0) {
            continue;
        }
        
        if (![line hasPrefix:@"OK "]) {
            
            NSLog (@"Failed to submit to server: %@", response);
            
//            NSAlert *alert = [[NSAlert alloc] init];
//            [alert addButtonWithTitle:FRLocalizedString(@"OK", nil)];
//            [alert setMessageText:FRLocalizedString(@"Sorry, failed to submit your feedback to the server.", nil)];
//            [alert setInformativeText:[NSString stringWithFormat:FRLocalizedString(@"Error: %@", nil), line]];
//            [alert setAlertStyle:NSWarningAlertStyle];
//            [alert runModal];
            
            return;
        }
    }
    
    [[NSUserDefaults standardUserDefaults] setValue:[NSDate date]
                                             forKey:DEFAULTS_KEY_LASTSUBMISSIONDATE];
    
    [[NSUserDefaults standardUserDefaults] setObject:self.controller.emailBoxText
                                              forKey:DEFAULTS_KEY_SENDEREMAIL];
    
    [self close];
}

- (void) show
{
    [super show];
    [self.controller show];
}

- (void) close
{
    [super close];
    [self.controller dismissViewControllerAnimated:YES completion:^{
        _controller = nil;
    }];
}

- (void) reset
{
    BOOL emailRequired = ( [self.emailRequiredTypes containsObject:self.type] || [self.emailStronglySuggestedTypes containsObject:self.type] );
    [self.controller resetWithEmailRequired:emailRequired];
}

@end
#endif
