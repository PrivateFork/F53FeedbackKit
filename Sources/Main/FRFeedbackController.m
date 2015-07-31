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
#import "FRCommand.h"
#import "FRApplication.h"
#import "FRCrashLogFinder.h"
#import "FRSystemProfile.h"
#import "FRConstants.h"
#import "FRConsoleLog.h"

#import "NSMutableDictionary+Additions.h"

#import <AddressBook/ABAddressBook.h>
#import <AddressBook/ABPerson.h>
#import <AddressBook/ABMultiValue.h>
#import <SystemConfiguration/SCNetwork.h>
#import <SystemConfiguration/SCNetworkReachability.h>


@implementation FRFeedbackController

#pragma mark Construction

- (id) init
{
    self = [super initWithWindowNibName:@"FeedbackReporter"];
    if (self != nil) {
        detailsShown = YES;
        documentList = nil;
        emailRequiredTypes = [NSArray arrayWithObject:FR_SUPPORT];
        emailStronglySuggestedTypes = [NSArray arrayWithObjects:FR_FEEDBACK, FR_CRASH, nil];
    }
    return self;
}

- (void) awakeFromNib
{
}

#pragma mark Destruction



#pragma mark Accessors

- (id) delegate
{
    return delegate;
}

- (void) setDelegate:(id) pDelegate
{
    delegate = pDelegate;
}

- (void) setHeading:(NSString*)message
{
    [headingField setStringValue:message];
}

- (void) setSubheading:(NSString *)informativeText
{
    [subheadingField setStringValue:informativeText];
}

- (void) setMessage:(NSString*)message
{
    [messageView setString:message];
}

- (void) setException:(NSString*)exception
{
    [exceptionView setString:exception];
}

- (void) setType:(NSString*)theType
{
    if (theType != type) {
        type = theType;
    }
}

#pragma mark information gathering

- (NSString*) consoleLog
{
    NSNumber *hours = [[[NSBundle mainBundle] infoDictionary] valueForKey:PLIST_KEY_LOGHOURS];

    int h = 24;

    if (hours != nil) {
        h = [hours intValue];
    }

    NSDate *since = [[NSCalendarDate calendarDate] dateByAddingYears:0 months:0 days:0 hours:-h minutes:0 seconds:0];

    NSNumber *maximumSize = [[[NSBundle mainBundle] infoDictionary] valueForKey:PLIST_KEY_MAXCONSOLELOGSIZE];

    return [FRConsoleLog logSince:since maxSize:maximumSize];
}


- (NSArray*) systemProfile
{
    static NSArray *systemProfile = nil;

    if (systemProfile == nil) {
        systemProfile = [FRSystemProfile discover];
    }

    return systemProfile;
}

- (NSString*) systemProfileAsString
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

- (NSString*) crashLog
{
    NSDate *lastSubmissionDate = [[NSUserDefaults standardUserDefaults] valueForKey:DEFAULTS_KEY_LASTSUBMISSIONDATE];

    NSArray *crashFiles = [FRCrashLogFinder findCrashLogsSince:lastSubmissionDate];

    NSUInteger i = [crashFiles count];

    if (i == 1) {
        if (lastSubmissionDate == nil) {
            NSLog(@"Found a crash file");
        } else {
            NSLog(@"Found a crash file earlier than latest submission on %@", lastSubmissionDate);
        }
        NSError *error = nil;
        NSString *result = [NSString stringWithContentsOfFile:[crashFiles lastObject] encoding: NSUTF8StringEncoding error:&error];
        if (result == nil) {
            NSLog(@"Failed to read crash file: %@", error);
            return @"";
        }
        return result;
    }

    if (lastSubmissionDate == nil) {
        NSLog(@"Found %lu crash files", (unsigned long)i);
    } else {
        NSLog(@"Found %lu crash files earlier than latest submission on %@", (unsigned long)i, lastSubmissionDate);
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSDate *newest = nil;
    NSInteger newestIndex = -1;

    while(i--) {

        NSString *crashFile = [crashFiles objectAtIndex:i];
        NSError* error = nil;
        NSDictionary *fileAttributes = [fileManager attributesOfItemAtPath:crashFile error:&error];
        if (!fileAttributes) {
            NSLog(@"Error while fetching file attributes: %@", [error localizedDescription]);
        }
        NSDate *fileModDate = [fileAttributes objectForKey:NSFileModificationDate];

        NSLog(@"CrashLog: %@", crashFile);

        if ([fileModDate laterDate:newest] == fileModDate) {
            newest = fileModDate;
            newestIndex = i;
        }

    }

    if (newestIndex != -1) {
        NSString *newestCrashFile = [crashFiles objectAtIndex:newestIndex];

        NSLog(@"Picking CrashLog: %@", newestCrashFile);

        NSError *error = nil;
        NSString *result = [NSString stringWithContentsOfFile:newestCrashFile encoding: NSUTF8StringEncoding error:&error];
        if (result == nil) {
            NSLog(@"Failed to read crash file: %@", error);
            return @"";
        }
        return result;
    }

    return @"";
}

- (NSString*) scriptLog
{
    NSMutableString *scriptLog = [NSMutableString string];

    NSString *scriptPath = [[NSBundle mainBundle] pathForResource:FILE_SHELLSCRIPT ofType:@"sh"];

    if ([[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) {

        FRCommand *cmd = [[FRCommand alloc] initWithPath:scriptPath];
        [cmd setOutput:scriptLog];
        [cmd setError:scriptLog];
        int ret = [cmd execute];

        NSLog(@"Script exit code = %d", ret);

    } /* else {
        NSLog(@"No custom script to execute");
    }
    */

    return scriptLog;
}

- (NSString*) preferences
{
    NSMutableDictionary *preferences = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:[FRApplication applicationIdentifier]] mutableCopy];

    if (preferences == nil) {
        return @"";
    }

    [preferences removeObjectForKey:DEFAULTS_KEY_SENDEREMAIL];

    if ([delegate respondsToSelector:@selector(anonymizePreferencesForFeedbackReport:)]) {
        preferences = [delegate anonymizePreferencesForFeedbackReport:preferences];
    }

    return [NSString stringWithFormat:@"%@", preferences];
}


#pragma mark UI Actions

- (void) showDetails:(BOOL)show animate:(BOOL)animate
{
    if (detailsShown == show) {
        return;
    }

    NSSize fullSize = NSMakeSize(455, 302);

    NSRect windowFrame = [[self window] frame];

    if (show) {

        windowFrame.origin.y -= fullSize.height;
        windowFrame.size.height += fullSize.height;
        [[self window] setFrame: windowFrame
                        display: YES
                        animate: animate];

    } else {
        windowFrame.origin.y += fullSize.height;
        windowFrame.size.height -= fullSize.height;
        [[self window] setFrame: windowFrame
                        display: YES
                        animate: animate];

    }

    detailsShown = show;
}

- (IBAction) showDetails:(id)sender
{
    BOOL show = [[sender objectValue] boolValue];
    [self showDetails:show animate:YES];
}

- (IBAction) sendDetailsChecked:(id)sender
{
    if ([sendDetailsCheckbox state] == NSOnState)
        [includeConsoleCheckbox setEnabled:YES];
    else
        [includeConsoleCheckbox setEnabled:NO];
}

- (IBAction) includeConsoleChecked:(id)sender
{
    if ([includeConsoleCheckbox state] == NSOnState) {
        [indicator setHidden:NO];
        [indicator startAnimation:self];
        [sendButton setEnabled:NO];
        [NSThread detachNewThreadSelector:@selector(loadConsole) toTarget:self withObject:nil];
    }
    else {
        [tabView removeTabViewItem:tabConsole];
    }
}

- (void)loadConsole
{
    @autoreleasepool {
        [self populateConsole];
        [self performSelectorOnMainThread:@selector(stopSpinner) withObject:self waitUntilDone:YES];
    }
}

- (IBAction) cancel:(id)sender
{
    [uploader cancel], uploader = nil;

    [self close];
}

- (IBAction) send:(id)sender
{
    if (uploader != nil) {
        NSLog(@"Still uploading");
        return;
    }
    
    // Check that email is present
    if ([emailBox stringValue] == nil || [[emailBox stringValue] isEqualToString:@""] || [[emailBox stringValue] isEqualToString:FRLocalizedString(@"anonymous", nil)]) {
        for (NSString *aType in emailRequiredTypes) {
            if ([aType isEqualToString:type]) {
                [[NSAlert alertWithMessageText:@"Email required" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"You must enter an email address so that we can respond to you."] runModal];
                return;
            }
        }
        for (NSString *aType in emailStronglySuggestedTypes) {
            if ([aType isEqualToString:type]) {
                NSInteger buttonPressed = [[NSAlert alertWithMessageText:@"Email missing" defaultButton:@"OK" alternateButton:@"Continue anyway" otherButton:nil informativeTextWithFormat:@"Email is missing. Without an email address, we cannot respond to you. Go back and enter one?"] runModal];
                if (buttonPressed == NSAlertDefaultReturn)
                    return;
                break;
            }
        }
    }

    NSString *target = [[FRApplication feedbackURL] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ;

    if ([[[FRFeedbackReporter sharedReporter] delegate] respondsToSelector:@selector(targetUrlForFeedbackReport)]) {
        target = [[[FRFeedbackReporter sharedReporter] delegate] targetUrlForFeedbackReport];
    }

    if (target == nil) {
        NSLog(@"You are missing the %@ key in your Info.plist!", PLIST_KEY_TARGETURL);
        return;
    }

    NSURL *url = [NSURL URLWithString:target];

    SCNetworkConnectionFlags reachabilityFlags = 0;

    NSString *host = [url host];
    const char *hostname = [host UTF8String];

    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, hostname);
    Boolean reachabilityResult = SCNetworkReachabilityGetFlags(reachability, &reachabilityFlags);
    CFRelease(reachability);

    // Prevent premature garbage collection (UTF8String returns an inner pointer).
    [host self];

    BOOL reachable = reachabilityResult
        &&  (reachabilityFlags & kSCNetworkFlagsReachable)
        && !(reachabilityFlags & kSCNetworkFlagsConnectionRequired)
        && !(reachabilityFlags & kSCNetworkFlagsConnectionAutomatic)
        && !(reachabilityFlags & kSCNetworkFlagsInterventionRequired);

    if (!reachable) {
        NSInteger alertResult = [[NSAlert alertWithMessageText:FRLocalizedString(@"Feedback Host Not Reachable", nil)
                                                 defaultButton:FRLocalizedString(@"Proceed Anyway", nil)
                                               alternateButton:FRLocalizedString(@"Cancel", nil)
                                                   otherButton:nil
                                     informativeTextWithFormat:FRLocalizedString(@"You may not be able to send feedback because %@ isn't reachable.", nil), host
                                  ] runModal];

        if (alertResult != NSAlertDefaultReturn) {
            return;
        }
    }

    uploader = [[FRUploader alloc] initWithTarget:target delegate:self];

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    [dict setValidString:[emailBox stringValue]
                  forKey:POST_KEY_EMAIL];

    [dict setValidString:[messageView string]
                  forKey:POST_KEY_MESSAGE];

    [dict setValidString:type
                  forKey:POST_KEY_TYPE];

    [dict setValidString:[FRApplication applicationLongVersion]
                  forKey:POST_KEY_VERSION_LONG];

    [dict setValidString:[FRApplication applicationShortVersion]
                  forKey:POST_KEY_VERSION_SHORT];

    [dict setValidString:[FRApplication applicationBundleVersion]
                  forKey:POST_KEY_VERSION_BUNDLE];

    [dict setValidString:[FRApplication applicationVersion]
                  forKey:POST_KEY_VERSION];

    if ([sendDetailsCheckbox state] == NSOnState) {
        if ([delegate respondsToSelector:@selector(customParametersForFeedbackReport)]) {
            [dict addEntriesFromDictionary:[delegate customParametersForFeedbackReport]];
        }

        [dict setValidString:[self systemProfileAsString]
                      forKey:POST_KEY_SYSTEM];

        if ([includeConsoleCheckbox state] == NSOnState)
            [dict setValidString:[consoleView string]
                          forKey:POST_KEY_CONSOLE];

        [dict setValidString:[crashesView string]
                      forKey:POST_KEY_CRASHES];

        [dict setValidString:[scriptView string]
                      forKey:POST_KEY_SHELL];

        [dict setValidString:[preferencesView string]
                      forKey:POST_KEY_PREFERENCES];

        [dict setValidString:[exceptionView string]
                      forKey:POST_KEY_EXCEPTION];
        
        if (documentList) {
            NSDictionary *documents = [documentList documentsToUpload];
            if (documents && [documents count] > 0)
                [dict setObject:documents forKey:POST_KEY_DOCUMENTS];
        }
    }

    NSLog(@"Sending feedback to %@", target);

    [uploader postAndNotify:dict];
}

- (void) uploaderStarted:(FRUploader*)pUploader
{
    // NSLog(@"Upload started");

    [indicator setHidden:NO];
    [indicator startAnimation:self];

    [messageView setEditable:NO];
    [sendButton setEnabled:NO];
}

- (void) uploaderFailed:(FRUploader*)pUploader withError:(NSError*)error
{
    NSLog(@"Upload failed: %@", error);

    [indicator stopAnimation:self];
    [indicator setHidden:YES];

    uploader = nil;

    [messageView setEditable:YES];
    [sendButton setEnabled:YES];

    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:FRLocalizedString(@"OK", nil)];
    [alert setMessageText:FRLocalizedString(@"Sorry, failed to submit your feedback to the server.", nil)];
    [alert setInformativeText:[NSString stringWithFormat:FRLocalizedString(@"Error: %@", nil), [error localizedDescription]]];
    [alert setAlertStyle:NSWarningAlertStyle];
    [alert runModal];

    [self close];
}

- (void) uploaderFinished:(FRUploader*)pUploader
{
    // NSLog(@"Upload finished");

    [indicator stopAnimation:self];
    [indicator setHidden:YES];

    NSString *response = [uploader response];

    uploader = nil;

    [messageView setEditable:YES];
    [sendButton setEnabled:YES];

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

    [[NSUserDefaults standardUserDefaults] setObject:[emailBox stringValue]
                                              forKey:DEFAULTS_KEY_SENDEREMAIL];

    [self close];
}

- (void) windowWillClose: (NSNotification *) n
{
    [uploader cancel];

    if ([type isEqualToString:FR_EXCEPTION]) {
        NSString *exitAfterException = [[[NSBundle mainBundle] infoDictionary] valueForKey:PLIST_KEY_EXITAFTEREXCEPTION];
        if (exitAfterException && [exitAfterException isEqualToString:@"YES"]) {
            // We want a pure exit() here I think.
            // As an exception has already been raised there is no
            // guarantee that the code path to [NSAapp terminate] is functional.
            // Calling abort() will crash the app here but is that more desirable?
            exit(EXIT_FAILURE);
        }
    }
}

- (void) windowDidLoad
{
    [[self window] setDelegate:self];

    [[self window] setTitle:FRLocalizedString(@"Feedback", nil)];
    [emailLabel setStringValue:FRLocalizedString(@"Email address:", nil)];
    [detailsLabel setStringValue:FRLocalizedString(@"Details", nil)];
    [tabSystem setLabel:FRLocalizedString(@"System", nil)];
    [tabConsole setLabel:FRLocalizedString(@"Console", nil)];
    [tabCrash setLabel:FRLocalizedString(@"CrashLog", nil)];
    [tabScript setLabel:FRLocalizedString(@"Script", nil)];
    [tabPreferences setLabel:FRLocalizedString(@"Preferences", nil)];
    [tabException setLabel:FRLocalizedString(@"Exception", nil)];

    [sendButton setTitle:FRLocalizedString(@"Send", nil)];
    [cancelButton setTitle:FRLocalizedString(@"Cancel", nil)];

    [[consoleView textContainer] setContainerSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    [[consoleView textContainer] setWidthTracksTextView:NO];
    [consoleView setString:@""];
    [[crashesView textContainer] setContainerSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    [[crashesView textContainer] setWidthTracksTextView:NO];
    [crashesView setString:@""];
    [[scriptView textContainer] setContainerSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    [[scriptView textContainer] setWidthTracksTextView:NO];
    [scriptView setString:@""];
    [[preferencesView textContainer] setContainerSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    [[preferencesView textContainer] setWidthTracksTextView:NO];
    [preferencesView setString:@""];
    [[exceptionView textContainer] setContainerSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    [[exceptionView textContainer] setWidthTracksTextView:NO];
    [exceptionView setString:@""];
}

- (void) stopSpinner
{
    [indicator stopAnimation:self];
    [indicator setHidden:YES];
    [sendButton setEnabled:YES];
}

- (void) addTabViewItem:(NSTabViewItem*)theTabViewItem
{
    [tabView insertTabViewItem:theTabViewItem atIndex:1];
}

- (void)populateConsole
{
    NSString *consoleLog = [self consoleLog];
    if ([consoleLog length] > 0) {
        [self performSelectorOnMainThread:@selector(addTabViewItem:) withObject:tabConsole waitUntilDone:YES];
        [consoleView performSelectorOnMainThread:@selector(setString:) withObject:consoleLog waitUntilDone:YES];
    }
}

- (void) populate
{
    @autoreleasepool {

        if ([includeConsoleCheckbox state] == NSOnState)
            [self populateConsole];

        NSString *crashLog = [self crashLog];
        if ([crashLog length] > 0) {
            [self performSelectorOnMainThread:@selector(addTabViewItem:) withObject:tabCrash waitUntilDone:YES];
            [crashesView performSelectorOnMainThread:@selector(setString:) withObject:crashLog waitUntilDone:YES];
        }

        NSString *scriptLog = [self scriptLog];
        if ([scriptLog length] > 0) {
            [self performSelectorOnMainThread:@selector(addTabViewItem:) withObject:tabScript waitUntilDone:YES];
            [scriptView performSelectorOnMainThread:@selector(setString:) withObject:scriptLog waitUntilDone:YES];
        }

        NSString *preferences = [self preferences];
        if ([preferences length] > 0) {
            [self performSelectorOnMainThread:@selector(addTabViewItem:) withObject:tabPreferences waitUntilDone:YES];
            [preferencesView performSelectorOnMainThread:@selector(setString:) withObject:preferences waitUntilDone:YES];
        }

        [self performSelectorOnMainThread:@selector(stopSpinner) withObject:self waitUntilDone:YES];

    }
}

- (void) reset
{
    [tabView removeTabViewItem:tabConsole];
    [tabView removeTabViewItem:tabCrash];
    [tabView removeTabViewItem:tabScript];
    [tabView removeTabViewItem:tabPreferences];
    [tabView removeTabViewItem:tabException];

    ABPerson *me = [[ABAddressBook sharedAddressBook] me];
    ABMutableMultiValue *emailAddresses = [me valueForProperty:kABEmailProperty];

    NSUInteger count = [emailAddresses count];

    [emailBox removeAllItems];

    [emailBox addItemWithObjectValue:FRLocalizedString(@"anonymous", nil)];

    for(NSUInteger i=0; i<count; i++) {

        NSString *emailAddress = [emailAddresses valueAtIndex:i];

        [emailBox addItemWithObjectValue:emailAddress];
    }

    NSString *email = [[NSUserDefaults standardUserDefaults] stringForKey:DEFAULTS_KEY_SENDEREMAIL];

    NSInteger found = [emailBox indexOfItemWithObjectValue:email];
    if (found != NSNotFound) {
        [emailBox selectItemAtIndex:found];
    } else if ([emailBox numberOfItems] >= 2) {
        NSString *defaultSender = [[[NSBundle mainBundle] infoDictionary] valueForKey:PLIST_KEY_DEFAULTSENDER];
        NSUInteger idx = (defaultSender && [defaultSender isEqualToString:@"firstEmail"]) ? 1 : 0;
        [emailBox selectItemAtIndex:idx];
    }
    
    if (([emailRequiredTypes containsObject:type] || [emailStronglySuggestedTypes containsObject:type]) &&
        ([emailBox stringValue] == nil || [[emailBox stringValue] isEqualToString:@""] || [[emailBox stringValue] isEqualToString:FRLocalizedString(@"anonymous", nil)])) {
        [emailLabel setTextColor:[NSColor redColor]];
    }
    else {
        [emailLabel setTextColor:[NSColor blackColor]];
    }


    [headingField setStringValue:@""];
    [messageView setString:@""];
    [exceptionView setString:@""];

    [self showDetails:NO animate:NO];
    [detailsButton setIntValue:NO];

    [indicator setHidden:NO];
    [indicator startAnimation:self];
    [sendButton setEnabled:NO];

    //  setup 'send details' checkbox...
    [sendDetailsCheckbox setTitle:FRLocalizedString(@"Send details", nil)];
    [sendDetailsCheckbox setState:NSOnState];
    NSString *sendDetailsIsOptional = [[[NSBundle mainBundle] infoDictionary] valueForKey:PLIST_KEY_SENDDETAILSISOPTIONAL];
    if (sendDetailsIsOptional && [sendDetailsIsOptional isEqualToString:@"YES"]) {
        [detailsLabel setHidden:YES];
        [sendDetailsCheckbox setHidden:NO];
        
        [sendDetailsCheckbox sizeToFit];
        [includeConsoleCheckbox sizeToFit];
        NSRect sendFrame = [sendDetailsCheckbox frame];
        NSRect consoleFrame = [includeConsoleCheckbox frame];
        CGFloat buffer = 20.0;
        consoleFrame.origin.x = sendFrame.origin.x + sendFrame.size.width + buffer;
        [includeConsoleCheckbox setFrame:consoleFrame];
        [includeConsoleCheckbox setState:NSOffState];
    } else {
        [detailsLabel setHidden:NO];
        [sendDetailsCheckbox setHidden:YES];
        [includeConsoleCheckbox setHidden:YES];
    }
}

- (void) showWindow:(id)sender
{
    documentList = [[FRDocumentList alloc] init];
    [documentList setupOtherButton:otherDocumentButton];
    [documentList setTableView:documentsView];
    [documentsView setDelegate:documentList];
    [documentsView setDataSource:documentList];
    [documentsView reloadData];
    
    if ([type isEqualToString:FR_FEEDBACK]) {
        [messageLabel setStringValue:FRLocalizedString(@"Feedback comment label", nil)];
    } else if ([type isEqualToString:FR_SUPPORT]) {
        [messageLabel setStringValue:FRLocalizedString(@"Describe the problem:", nil)];
    } else {
        [messageLabel setStringValue:FRLocalizedString(@"Comments:", nil)];
    }

    if ([[exceptionView string] length] != 0) {
        [tabView insertTabViewItem:tabException atIndex:1];
        [tabView selectTabViewItemWithIdentifier:@"Exception"];
    } else {
        [tabView selectTabViewItemWithIdentifier:@"System"];
    }
    
    if ([type isEqual:FR_SUPPORT]) {
        [self showDetails:YES animate:NO];
        [detailsButton setState:NSOnState];
        if ([[documentList docs] count] > 0)
            [tabView selectTabViewItemWithIdentifier:@"Documents"];
    }

    [NSThread detachNewThreadSelector:@selector(populate) toTarget:self withObject:nil];

    [super showWindow:sender];
}

- (BOOL) isShown
{
    return [[self window] isVisible];
}


@end
