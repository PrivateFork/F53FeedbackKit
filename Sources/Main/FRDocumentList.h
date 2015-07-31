//
//  FRDocumentList.h
//  F53FeedbackKit
//
//  Created by Chad Sellers on 11/1/12.
//
//

#import <Cocoa/Cocoa.h>

@interface FRDocumentList : NSObject <NSTableViewDelegate, NSTableViewDataSource>
{
    NSMutableArray          *_docs;
    NSMutableDictionary     *_selectionState;
    NSTableView             *__strong _tableView;
}
- (void)selectMostRecentDocument;
- (void)setupOtherButton:(NSButton *)otherButton;
- (NSDictionary *)documentsToUpload; // key = filename, value = NSString of base64 encoded file data
@property(readwrite, strong, nonatomic) NSMutableArray *docs;
@property(readwrite, strong, nonatomic) NSMutableDictionary *selectionState;
@property(readwrite, strong, nonatomic) NSTableView *tableView;
@end
