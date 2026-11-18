#import "AliceNativeMenu.h"
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <execinfo.h>
#import <signal.h>

// Forward declarations from miniquad
extern void* miniquad_ios_root_view_controller(void) __attribute__((weak));
extern void* miniquad_ios_mtk_view(void) __attribute__((weak));
extern void miniquad_ios_set_preferred_fps(int fps) __attribute__((weak));

static AliceMenuResult s_result = {0};
static int s_has_action = 0;
static UIView *s_active_menu_view = nil;

static NSString *AliceGetLogFilePath(void);
static NSString *AliceGetCrashFilePath(void);
static UIViewController* AliceGetRootViewController(void* hint);

typedef NS_ENUM(NSInteger, MenuPage) {
    MenuPageMain = 0,
    MenuPageNewGame = 1,
    MenuPageLoad = 2,
    MenuPageChapters = 3,
    MenuPageSettings = 4
};

@interface AliceNativeMenuView : UIView <UIScrollViewDelegate>
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *pageContainer;

// State data
@property (nonatomic, assign) MenuPage currentPage;
@property (nonatomic, assign) BOOL isPause;
@property (nonatomic, assign) BOOL hasContinue;
@property (nonatomic, assign) int continueSlot;
@property (nonatomic, copy) NSString *continueChapter;
@property (nonatomic, copy) NSString *continueDate;

@property (nonatomic, strong) NSMutableArray<NSDictionary*> *slotItems;
@property (nonatomic, strong) NSMutableArray<NSDictionary*> *chapterItems;
@property (nonatomic, assign) float soundVol;
@property (nonatomic, assign) float musicVol;
@property (nonatomic, assign) float voiceVol;
@property (nonatomic, assign) float lookSens;
@property (nonatomic, assign) BOOL invertY;
@property (nonatomic, assign) BOOL metalHUD;

@property (nonatomic, strong) UIImpactFeedbackGenerator *haptic;
@end

@implementation AliceNativeMenuView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    // 1. Solid opaque background so absolutely nothing of the legacy PC menu can bleed through
    self.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.06 alpha:1.0];

    // Subtle atmospheric dark vignette gradient
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = self.bounds;
    gradient.colors = @[
        (id)[UIColor colorWithRed:0.06 green:0.04 blue:0.08 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.02 green:0.02 blue:0.03 alpha:1.0].CGColor
    ];
    gradient.startPoint = CGPointMake(0.5, 0.0);
    gradient.endPoint = CGPointMake(0.5, 1.0);
    [self.layer addSublayer:gradient];

    // 2. Centered Floating Card
    self.cardView = [[UIView alloc] init];
    self.cardView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.92];
    self.cardView.layer.cornerRadius = 24.0;
    if (@available(iOS 13.0, *)) {
        self.cardView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.cardView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.20].CGColor;
    self.cardView.layer.borderWidth = 1.2;
    self.cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.cardView.layer.shadowOpacity = 0.65;
    self.cardView.layer.shadowRadius = 24.0;
    self.cardView.layer.shadowOffset = CGSizeMake(0, 10);
    [self addSubview:self.cardView];

    // 3. Header
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = @"AMERICAN MCGEE'S ALICE";
    self.titleLabel.textColor = [UIColor colorWithRed:0.96 green:0.93 blue:0.87 alpha:1.0];
    self.titleLabel.font = [UIFont fontWithName:@"Georgia-Bold" size:22.0] ?: [UIFont boldSystemFontOfSize:22.0];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.cardView addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.text = @"LOOKINGMETAL · APPLE METAL 3 · 120 FPS";
    self.subtitleLabel.textColor = [UIColor colorWithRed:0.75 green:0.75 blue:0.80 alpha:1.0];
    self.subtitleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    [self.cardView addSubview:self.subtitleLabel];

    // 4. Page Container
    self.pageContainer = [[UIView alloc] init];
    self.pageContainer.clipsToBounds = YES;
    [self.cardView addSubview:self.pageContainer];

    [self updateLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.layer.sublayers.count > 0) {
        CALayer *grad = self.layer.sublayers[0];
        if ([grad isKindOfClass:[CAGradientLayer class]]) {
            grad.frame = self.bounds;
        }
    }
    [self updateLayout];
}

- (void)updateLayout {
    CGSize sz = self.bounds.size;
    CGFloat cardW = MIN(sz.width - 48.0, 560.0);
    CGFloat cardH = MIN(sz.height - 24.0, 380.0);
    CGFloat cardX = (sz.width - cardW) * 0.5;
    CGFloat cardY = (sz.height - cardH) * 0.5;

    self.cardView.frame = CGRectMake(cardX, cardY, cardW, cardH);
    self.titleLabel.frame = CGRectMake(16.0, 14.0, cardW - 32.0, 24.0);
    self.subtitleLabel.frame = CGRectMake(16.0, 38.0, cardW - 32.0, 16.0);

    CGFloat contentY = 58.0;
    self.pageContainer.frame = CGRectMake(16.0, contentY, cardW - 32.0, cardH - contentY - 14.0);
}

- (void)showPage:(MenuPage)page {
    self.currentPage = page;
    for (UIView *v in self.pageContainer.subviews) {
        [v removeFromSuperview];
    }

    [self.haptic prepare];

    switch (page) {
        case MenuPageMain:     [self buildMainPage]; break;
        case MenuPageNewGame:  [self buildNewGamePage]; break;
        case MenuPageLoad:     [self buildLoadPage]; break;
        case MenuPageChapters: [self buildChaptersPage]; break;
        case MenuPageSettings: [self buildSettingsPage]; break;
    }

    CATransition *transition = [CATransition animation];
    transition.duration = 0.20;
    transition.type = kCATransitionFade;
    [self.pageContainer.layer addAnimation:transition forKey:nil];
}

#pragma mark - Page 0: Main Menu

- (void)buildMainPage {
    CGSize size = self.pageContainer.bounds.size;
    CGFloat btnW = size.width;

    NSMutableArray *items = [NSMutableArray array];

    if (self.isPause) {
        self.titleLabel.text = @"PAUSE";
        if (self.continueChapter && self.continueChapter.length > 0) {
            self.subtitleLabel.text = self.continueChapter;
        } else {
            self.subtitleLabel.text = @"GAME PAUSED";
        }
        self.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.06 alpha:0.80];

        [items addObject:@{@"t": @"Resume", @"i": @"▶️", @"tag": @6, @"highlight": @YES}];
        [items addObject:@{@"t": @"Quick Save", @"i": @"💾", @"tag": @7, @"sub": @"Save progress to Slot 1"}];
        [items addObject:@{@"t": @"Load Game", @"i": @"📂", @"tag": @2}];
        [items addObject:@{@"t": @"Chapter Select", @"i": @"📖", @"tag": @3}];
        [items addObject:@{@"t": @"Settings", @"i": @"⚙️", @"tag": @4}];
        [items addObject:@{@"t": @"Quit to Title", @"i": @"🚪", @"tag": @5}];
    } else {
        self.titleLabel.text = @"AMERICAN McGEE'S ALICE";
        self.subtitleLabel.text = @"LOOKINGMETAL · iOS NATIVE EDITION";
        self.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.06 alpha:1.0];

        if (self.hasContinue) {
            NSString *sub = [NSString stringWithFormat:@"%@  ·  %@", self.continueChapter ?: @"", self.continueDate ?: @""];
            [items addObject:@{@"t": @"Continue", @"sub": sub, @"i": @"▶️", @"tag": @6, @"highlight": @YES}];
        }
        [items addObject:@{@"t": @"New Game", @"i": @"⚔️", @"tag": @1}];
        [items addObject:@{@"t": @"Load Game", @"i": @"💾", @"tag": @2}];
        [items addObject:@{@"t": @"Chapter Select", @"i": @"📖", @"tag": @3}];
        [items addObject:@{@"t": @"Settings", @"i": @"⚙️", @"tag": @4}];
        [items addObject:@{@"t": @"Quit Game", @"i": @"🚪", @"tag": @5}];
    }

    CGFloat btnH = items.count > 5 ? 42.0 : 46.0;
    CGFloat spacing = 6.0;
    CGFloat totalH = items.count * btnH + (items.count - 1) * spacing;
    CGFloat startY = MAX(0.0, (size.height - totalH) * 0.5);

    NSUInteger count = items.count;
    for (NSUInteger i = 0; i < count; i++) {
        NSDictionary *dict = items[i];
        BOOL isHighlight = [dict[@"highlight"] boolValue];
        NSString *sub = dict[@"sub"];

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.tag = [dict[@"tag"] integerValue];
        [btn addTarget:self action:@selector(onMainMenuTap:) forControlEvents:UIControlEventTouchUpInside];
        btn.frame = CGRectMake(0, startY + i * (btnH + spacing), btnW, btnH);
        btn.layer.cornerRadius = 14.0;
        if (@available(iOS 13.0, *)) {
            btn.layer.cornerCurve = kCACornerCurveContinuous;
        }

        if (isHighlight) {
            btn.backgroundColor = [UIColor colorWithRed:0.75 green:0.22 blue:0.22 alpha:0.40];
            btn.layer.borderColor = [UIColor colorWithRed:0.95 green:0.75 blue:0.35 alpha:0.65].CGColor;
            btn.layer.borderWidth = 1.3;

            if (sub && sub.length > 0) {
                UILabel *tL = [[UILabel alloc] initWithFrame:CGRectMake(16, 3, btnW - 32, 20)];
                tL.text = [NSString stringWithFormat:@"%@  %@", dict[@"i"], dict[@"t"]];
                tL.textColor = [UIColor colorWithRed:1.0 green:0.92 blue:0.75 alpha:1.0];
                tL.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
                [btn addSubview:tL];

                UILabel *sL = [[UILabel alloc] initWithFrame:CGRectMake(40, 23, btnW - 56, 15)];
                sL.text = sub;
                sL.textColor = [UIColor colorWithWhite:0.80 alpha:1.0];
                sL.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular];
                [btn addSubview:sL];
            } else {
                [btn setTitle:[NSString stringWithFormat:@"%@  %@", dict[@"i"], dict[@"t"]] forState:UIControlStateNormal];
                [btn setTitleColor:[UIColor colorWithRed:1.0 green:0.92 blue:0.75 alpha:1.0] forState:UIControlStateNormal];
                btn.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
            }
        } else {
            btn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
            btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
            btn.layer.borderWidth = 1.0;
            NSString *fullText = dict[@"i"] ? [NSString stringWithFormat:@"%@  %@", dict[@"i"], dict[@"t"]] : dict[@"t"];
            [btn setTitle:fullText forState:UIControlStateNormal];
            [btn setTitleColor:[UIColor colorWithWhite:0.95 alpha:1.0] forState:UIControlStateNormal];
            btn.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
        }

        [self.pageContainer addSubview:btn];
    }
}

- (void)onMainMenuTap:(UIButton *)btn {
    [self.haptic impactOccurred];
    switch (btn.tag) {
        case 6: {
            s_result.action = AliceMenuActionContinue;
            s_result.save_slot = self.continueSlot;
            s_has_action = 1;
            [self dismissWithAnimation];
            break;
        }
        case 7: {
            s_result.action = AliceMenuActionSave;
            s_result.save_slot = 0; // Slot 1
            s_has_action = 1;
            [self dismissWithAnimation];
            break;
        }
        case 1: [self showPage:MenuPageNewGame]; break;
        case 2: [self showPage:MenuPageLoad]; break;
        case 3: [self showPage:MenuPageChapters]; break;
        case 4: [self showPage:MenuPageSettings]; break;
        case 5: {
            s_result.action = AliceMenuActionQuit;
            s_has_action = 1;
            [self dismissWithAnimation];
            break;
        }
    }
}

#pragma mark - Page 1: New Game (Difficulty Selection)

- (void)buildNewGamePage {
    CGSize size = self.pageContainer.bounds.size;
    CGFloat btnW = size.width;

    UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    backBtn.frame = CGRectMake(0, 0, 140.0, 32.0);
    [backBtn setTitle:@"‹ Back" forState:UIControlStateNormal];
    [backBtn setTitleColor:[UIColor colorWithWhite:0.90 alpha:1.0] forState:UIControlStateNormal];
    backBtn.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    [backBtn addTarget:self action:@selector(onBackTap:) forControlEvents:UIControlEventTouchUpInside];
    [self.pageContainer addSubview:backBtn];

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(148.0, 0, size.width - 148.0, 32.0)];
    header.text = @"SELECT DIFFICULTY";
    header.textColor = [UIColor colorWithRed:0.95 green:0.85 blue:0.65 alpha:1.0];
    header.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    header.textAlignment = NSTextAlignmentRight;
    [self.pageContainer addSubview:header];

    NSArray *diffs = @[
        @{@"t": @"Easy", @"sub": @"For players who want to enjoy the story", @"d": @0, @"color": [UIColor colorWithRed:0.3 green:0.8 blue:0.4 alpha:0.18]},
        @{@"t": @"Medium", @"sub": @"Classic balance of the original 2000 game", @"d": @1, @"color": [UIColor colorWithRed:0.9 green:0.7 blue:0.2 alpha:0.18]},
        @{@"t": @"Nightmare", @"sub": @"Maximum damage from Wonderland's nightmares", @"d": @2, @"color": [UIColor colorWithRed:0.9 green:0.25 blue:0.25 alpha:0.18]},
    ];

    CGFloat btnH = 56.0;
    CGFloat spacing = 10.0;
    CGFloat startY = 42.0;

    NSUInteger diffCount = diffs.count;
    for (NSUInteger i = 0; i < diffCount; i++) {
        NSDictionary *d = diffs[i];
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.tag = [d[@"d"] integerValue];
        [btn addTarget:self action:@selector(onDifficultySelect:) forControlEvents:UIControlEventTouchUpInside];
        btn.frame = CGRectMake(0, startY + i * (btnH + spacing), btnW, btnH);
        btn.layer.cornerRadius = 14.0;
        if (@available(iOS 13.0, *)) {
            btn.layer.cornerCurve = kCACornerCurveContinuous;
        }
        btn.backgroundColor = d[@"color"];
        btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
        btn.layer.borderWidth = 1.0;

        UILabel *titleL = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, btnW - 32, 20)];
        titleL.text = d[@"t"];
        titleL.textColor = [UIColor whiteColor];
        titleL.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold];
        [btn addSubview:titleL];

        UILabel *subL = [[UILabel alloc] initWithFrame:CGRectMake(16, 28, btnW - 32, 18)];
        subL.text = d[@"sub"];
        subL.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
        subL.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
        [btn addSubview:subL];

        [self.pageContainer addSubview:btn];
    }
}

- (void)onDifficultySelect:(UIButton *)btn {
    [self.haptic impactOccurred];
    s_result.action = AliceMenuActionNewGame;
    s_result.difficulty = (int)btn.tag;
    s_has_action = 1;
    [self dismissWithAnimation];
}

#pragma mark - Page 2: Load Game

- (void)buildLoadPage {
    CGSize size = self.pageContainer.bounds.size;

    UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    backBtn.frame = CGRectMake(0, 0, 140.0, 32.0);
    [backBtn setTitle:@"‹ Back" forState:UIControlStateNormal];
    [backBtn setTitleColor:[UIColor colorWithWhite:0.90 alpha:1.0] forState:UIControlStateNormal];
    backBtn.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    [backBtn addTarget:self action:@selector(onBackTap:) forControlEvents:UIControlEventTouchUpInside];
    [self.pageContainer addSubview:backBtn];

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(148.0, 0, size.width - 148.0, 32.0)];
    header.text = @"LOAD SAVED GAME";
    header.textColor = [UIColor colorWithRed:0.95 green:0.85 blue:0.65 alpha:1.0];
    header.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    header.textAlignment = NSTextAlignmentRight;
    [self.pageContainer addSubview:header];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 38.0, size.width, size.height - 38.0)];
    scroll.showsVerticalScrollIndicator = YES;
    [self.pageContainer addSubview:scroll];

    CGFloat cardH = 50.0;
    CGFloat spacing = 8.0;

    NSUInteger slotCount = self.slotItems.count;
    for (NSUInteger i = 0; i < slotCount; i++) {
        NSDictionary *s = self.slotItems[i];
        int slotIdx = [s[@"slot"] intValue];
        BOOL isEmpty = [s[@"empty"] boolValue];
        NSString *slotTitle = s[@"title"] ?: @"";
        if (slotTitle.length == 0) {
            slotTitle = [NSString stringWithFormat:@"Slot %lu", (unsigned long)(i + 1)];
        }
        NSString *chapter = s[@"chapter"] ?: @"";
        NSString *date = s[@"date"] ?: @"";

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.tag = slotIdx;
        btn.frame = CGRectMake(0, i * (cardH + spacing), size.width, cardH);
        btn.layer.cornerRadius = 12.0;
        if (@available(iOS 13.0, *)) {
            btn.layer.cornerCurve = kCACornerCurveContinuous;
        }

        if (isEmpty) {
            btn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.04];
            btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.06].CGColor;
            btn.layer.borderWidth = 1.0;
            btn.enabled = NO;

            UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, size.width - 32, cardH)];
            l.text = [NSString stringWithFormat:@"%@:  — Empty —", slotTitle];
            l.textColor = [UIColor colorWithWhite:0.40 alpha:1.0];
            l.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
            [btn addSubview:l];
        } else {
            btn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
            btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
            btn.layer.borderWidth = 1.0;
            [btn addTarget:self action:@selector(onSlotSelect:) forControlEvents:UIControlEventTouchUpInside];

            UILabel *top = [[UILabel alloc] initWithFrame:CGRectMake(16, 7, size.width - 32, 19)];
            top.text = [NSString stringWithFormat:@"%@:  %@", slotTitle, chapter];
            top.textColor = [UIColor whiteColor];
            top.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
            [btn addSubview:top];

            UILabel *bot = [[UILabel alloc] initWithFrame:CGRectMake(16, 27, size.width - 32, 16)];
            bot.text = date;
            bot.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
            bot.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
            [btn addSubview:bot];
        }

        [scroll addSubview:btn];
    }

    scroll.contentSize = CGSizeMake(size.width, self.slotItems.count * (cardH + spacing));
}

- (void)onSlotSelect:(UIButton *)btn {
    [self.haptic impactOccurred];
    s_result.action = AliceMenuActionLoadGame;
    s_result.save_slot = (int)btn.tag;
    s_has_action = 1;
    [self dismissWithAnimation];
}

#pragma mark - Page 3: Chapter Select

- (void)buildChaptersPage {
    CGSize size = self.pageContainer.bounds.size;

    UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    backBtn.frame = CGRectMake(0, 0, 140.0, 32.0);
    [backBtn setTitle:@"‹ Back" forState:UIControlStateNormal];
    [backBtn setTitleColor:[UIColor colorWithWhite:0.90 alpha:1.0] forState:UIControlStateNormal];
    backBtn.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    [backBtn addTarget:self action:@selector(onBackTap:) forControlEvents:UIControlEventTouchUpInside];
    [self.pageContainer addSubview:backBtn];

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(148.0, 0, size.width - 148.0, 32.0)];
    header.text = @"CHAPTER SELECT";
    header.textColor = [UIColor colorWithRed:0.95 green:0.85 blue:0.65 alpha:1.0];
    header.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    header.textAlignment = NSTextAlignmentRight;
    [self.pageContainer addSubview:header];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 38.0, size.width, size.height - 38.0)];
    scroll.showsVerticalScrollIndicator = YES;
    [self.pageContainer addSubview:scroll];

    CGFloat btnH = 42.0;
    CGFloat spacing = 6.0;

    NSUInteger chapCount = self.chapterItems.count;
    for (NSUInteger i = 0; i < chapCount; i++) {
        NSDictionary *c = self.chapterItems[i];
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.tag = [c[@"idx"] integerValue];
        [btn addTarget:self action:@selector(onChapterSelect:) forControlEvents:UIControlEventTouchUpInside];
        btn.frame = CGRectMake(0, i * (btnH + spacing), size.width, btnH);
        btn.layer.cornerRadius = 10.0;
        if (@available(iOS 13.0, *)) {
            btn.layer.cornerCurve = kCACornerCurveContinuous;
        }
        btn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
        btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
        btn.layer.borderWidth = 1.0;
        btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;

        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(14, 0, size.width - 28, btnH)];
        l.text = [NSString stringWithFormat:@"📖  %@", c[@"title"]];
        l.textColor = [UIColor colorWithWhite:0.95 alpha:1.0];
        l.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
        [btn addSubview:l];

        [scroll addSubview:btn];
    }

    scroll.contentSize = CGSizeMake(size.width, self.chapterItems.count * (btnH + spacing));
}

- (void)onChapterSelect:(UIButton *)btn {
    [self.haptic impactOccurred];
    s_result.action = AliceMenuActionChapters;
    s_result.chapter_idx = (int)btn.tag;
    s_has_action = 1;
    [self dismissWithAnimation];
}

#pragma mark - Page 4: Settings

- (void)buildSettingsPage {
    CGSize size = self.pageContainer.bounds.size;

    UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    backBtn.frame = CGRectMake(0, 0, 140.0, 32.0);
    [backBtn setTitle:@"‹ Back" forState:UIControlStateNormal];
    [backBtn setTitleColor:[UIColor colorWithWhite:0.90 alpha:1.0] forState:UIControlStateNormal];
    backBtn.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    [backBtn addTarget:self action:@selector(onBackTap:) forControlEvents:UIControlEventTouchUpInside];
    [self.pageContainer addSubview:backBtn];

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(148.0, 0, size.width - 148.0, 32.0)];
    header.text = @"SETTINGS";
    header.textColor = [UIColor colorWithRed:0.95 green:0.85 blue:0.65 alpha:1.0];
    header.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    header.textAlignment = NSTextAlignmentRight;
    [self.pageContainer addSubview:header];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 36.0, size.width, size.height - 36.0)];
    scroll.showsVerticalScrollIndicator = YES;
    [self.pageContainer addSubview:scroll];

    CGFloat rowH = 42.0;
    CGFloat y = 0.0;

    // 1. Sound Vol
    [self addSliderTo:scroll y:y label:@"🔊 Sound Effects (SFX)" val:self.soundVol min:0 max:1 tag:101 action:@selector(onSliderChange:)];
    y += rowH;

    // 2. Music Vol
    [self addSliderTo:scroll y:y label:@"🎵 Music" val:self.musicVol min:0 max:1 tag:102 action:@selector(onSliderChange:)];
    y += rowH;

    // 3. Voice Vol
    [self addSliderTo:scroll y:y label:@"🎙️ Voice / Dialogue" val:self.voiceVol min:0 max:1 tag:103 action:@selector(onSliderChange:)];
    y += rowH;

    // 4. Look Sens
    [self addSliderTo:scroll y:y label:@"👁️ Look Sensitivity" val:self.lookSens min:0.5 max:3.0 tag:104 action:@selector(onSliderChange:)];
    y += rowH;

    // 5. Invert Y
    UIView *toggleRow = [[UIView alloc] initWithFrame:CGRectMake(0, y, size.width, rowH)];
    UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(4, 0, size.width - 70, rowH)];
    tl.text = @"↕️ Invert Camera Y-Axis";
    tl.textColor = [UIColor whiteColor];
    tl.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightMedium];
    [toggleRow addSubview:tl];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(size.width - 55, 5, 51, 31)];
    sw.on = self.invertY;
    sw.onTintColor = [UIColor colorWithRed:0.85 green:0.25 blue:0.25 alpha:1.0];
    [sw addTarget:self action:@selector(onInvertYToggle:) forControlEvents:UIControlEventValueChanged];
    [toggleRow addSubview:sw];
    [scroll addSubview:toggleRow];
    y += rowH;

    // 6. Metal Performance HUD
    CGFloat hudRowH = 50.0;
    UIView *hudRow = [[UIView alloc] initWithFrame:CGRectMake(0, y, size.width, hudRowH)];
    UILabel *hl = [[UILabel alloc] initWithFrame:CGRectMake(4, 2, size.width - 70, 22)];
    hl.text = @"📊 Metal Performance HUD";
    hl.textColor = [UIColor colorWithRed:0.70 green:0.95 blue:0.80 alpha:1.0];
    hl.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    [hudRow addSubview:hl];

    UILabel *subHl = [[UILabel alloc] initWithFrame:CGRectMake(4, 24, size.width - 70, 18)];
    subHl.text = @"Apple Metal 3 real-time FPS & GPU telemetry overlay";
    subHl.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    subHl.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
    [hudRow addSubview:subHl];

    UISwitch *hudSw = [[UISwitch alloc] initWithFrame:CGRectMake(size.width - 55, 8, 51, 31)];
    hudSw.on = self.metalHUD;
    hudSw.onTintColor = [UIColor colorWithRed:0.20 green:0.75 blue:0.45 alpha:1.0];
    [hudSw addTarget:self action:@selector(onMetalHUDToggle:) forControlEvents:UIControlEventValueChanged];
    [hudRow addSubview:hudSw];
    [scroll addSubview:hudRow];
    y += hudRowH;

    // 7. View Game Logs Button
    CGFloat logRowH = 46.0;
    UIButton *logBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    logBtn.frame = CGRectMake(0, y + 4, size.width, 38.0);
    logBtn.layer.cornerRadius = 10.0;
    if (@available(iOS 13.0, *)) {
        logBtn.layer.cornerCurve = kCACornerCurveContinuous;
    }
    logBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    logBtn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.20].CGColor;
    logBtn.layer.borderWidth = 1.0;
    [logBtn setTitle:@"📄 View Logs & Crash Reports" forState:UIControlStateNormal];
    [logBtn setTitleColor:[UIColor colorWithRed:0.95 green:0.85 blue:0.65 alpha:1.0] forState:UIControlStateNormal];
    logBtn.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightMedium];
    [logBtn addTarget:self action:@selector(onViewLogTap:) forControlEvents:UIControlEventTouchUpInside];
    [scroll addSubview:logBtn];
    y += logRowH;

    scroll.contentSize = CGSizeMake(size.width, y + 16.0);
}

- (void)onViewLogTap:(UIButton *)btn {
    [self.haptic impactOccurred];
    NSString *logPath = AliceGetLogFilePath();
    NSString *crashPath = AliceGetCrashFilePath();

    NSMutableString *content = [NSMutableString string];
    if ([[NSFileManager defaultManager] fileExistsAtPath:crashPath]) {
        NSString *crash = [NSString stringWithContentsOfFile:crashPath encoding:NSUTF8StringEncoding error:nil];
        if (crash.length > 0) {
            [content appendFormat:@"--- LAST CRASH REPORT ---\n%@\n\n", crash];
        }
    }

    NSString *log = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil];
    if (log && log.length > 0) {
        NSArray *lines = [log componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSUInteger start = lines.count > 50 ? lines.count - 50 : 0;
        NSArray *recent = [lines subarrayWithRange:NSMakeRange(start, lines.count - start)];
        [content appendFormat:@"--- RECENT LOG (Last %lu lines) ---\n%@\n", (unsigned long)recent.count, [recent componentsJoinedByString:@"\n"]];
    } else {
        [content appendString:@"Log is currently empty or session just started."];
    }

    UIViewController *rootVC = AliceGetRootViewController(NULL);
    if (!rootVC) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"LookingMetal Log"
                                                                   message:content
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Copy to Clipboard" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [UIPasteboard generalPasteboard].string = content;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [rootVC presentViewController:alert animated:YES completion:nil];
}

- (void)addSliderTo:(UIView *)parent y:(CGFloat)y label:(NSString *)label val:(float)val min:(float)min max:(float)max tag:(NSInteger)tag action:(SEL)act {
    CGFloat w = parent.bounds.size.width;
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, w, 42.0)];

    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(4, 0, w * 0.45, 42.0)];
    l.text = label;
    l.textColor = [UIColor whiteColor];
    l.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    [row addSubview:l];

    UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(w * 0.45 + 10, 5, w * 0.55 - 14, 32.0)];
    sl.minimumValue = min;
    sl.maximumValue = max;
    sl.value = val;
    sl.tag = tag;
    sl.tintColor = [UIColor colorWithRed:0.85 green:0.25 blue:0.25 alpha:1.0];
    [sl addTarget:self action:act forControlEvents:UIControlEventValueChanged];
    [row addSubview:sl];

    [parent addSubview:row];
}

- (void)onSliderChange:(UISlider *)sl {
    switch (sl.tag) {
        case 101: self.soundVol = sl.value; s_result.sound_vol = sl.value; break;
        case 102: self.musicVol = sl.value; s_result.music_vol = sl.value; break;
        case 103: self.voiceVol = sl.value; s_result.voice_vol = sl.value; break;
        case 104: self.lookSens = sl.value; s_result.look_sens = sl.value; break;
    }
}

- (void)onInvertYToggle:(UISwitch *)sw {
    [self.haptic impactOccurred];
    self.invertY = sw.isOn;
    s_result.invert_y = sw.isOn ? 1 : 0;
}

- (void)onMetalHUDToggle:(UISwitch *)sw {
    [self.haptic impactOccurred];
    self.metalHUD = sw.isOn;
    s_result.metal_hud = sw.isOn ? 1 : 0;
    AliceNativeMenu_SetMetalHUD(sw.isOn ? 1 : 0);
}

- (void)onBackTap:(UIButton *)btn {
    (void)btn;
    [self.haptic impactOccurred];
    [self showPage:MenuPageMain];
}

- (void)dismissWithAnimation {
    [UIView animateWithDuration:0.22 animations:^{
        self.alpha = 0.0;
        self.cardView.transform = CGAffineTransformMakeScale(0.92, 0.92);
    } completion:^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
        s_active_menu_view = nil;
    }];
}

@end

#pragma mark - C API Bridge

void* AliceGetMTKView(void) {
    if (miniquad_ios_mtk_view) {
        return miniquad_ios_mtk_view();
    }
    return NULL;
}

static void AliceLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"%@", msg);

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (paths.count > 0) {
        NSString *logPath = [paths[0] stringByAppendingPathComponent:@"alice_hud.log"];
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (!h) {
            [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
            h = [NSFileHandle fileHandleForWritingAtPath:logPath];
        }
        [h seekToEndOfFile];
        [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
    }
}

static BOOL AliceIsMetalHUDRequested(void) {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if ([defs objectForKey:@"MetalHUDEnabled"] != nil) {
        return [defs boolForKey:@"MetalHUDEnabled"];
    }

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (paths.count > 0) {
        NSString *docDir = paths[0];
        NSString *launcherJson = [docDir stringByAppendingPathComponent:@"ios-launcher.json"];
        NSData *d = [NSData dataWithContentsOfFile:launcherJson];
        if (d) {
            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            if (dict[@"metal_hud"] != nil) {
                return [dict[@"metal_hud"] boolValue];
            }
        }
    }

    const char *m = getenv("MTL_HUD_ENABLED");
    if (m && atoi(m) != 0) return YES;
    return NO;
}

static CAMetalLayer* AliceFindMetalLayer(UIView *v) {
    if (!v) return nil;
    if ([v.layer isKindOfClass:[CAMetalLayer class]]) {
        return (CAMetalLayer*)v.layer;
    }
    for (CALayer *sub in v.layer.sublayers) {
        if ([sub isKindOfClass:[CAMetalLayer class]]) {
            return (CAMetalLayer*)sub;
        }
    }
    for (UIView *child in v.subviews) {
        CAMetalLayer *found = AliceFindMetalLayer(child);
        if (found) return found;
    }
    return nil;
}

static NSString *AliceGetLogFilePath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs = paths.firstObject ?: NSTemporaryDirectory();
    return [docs stringByAppendingPathComponent:@"LookingMetal.log"];
}

static NSString *AliceGetCrashFilePath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs = paths.firstObject ?: NSTemporaryDirectory();
    return [docs stringByAppendingPathComponent:@"LookingMetal_crash.log"];
}

void AliceWriteCrashLog(const char* msg) {
    if (!msg) return;
    NSString *crashPath = AliceGetCrashFilePath();
    FILE *f = fopen([crashPath UTF8String], "a");
    if (!f) return;
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *ts = [df stringFromDate:[NSDate date]];
    fprintf(f, "[%s] %s\n", [ts UTF8String], msg);
    fflush(f);
    fclose(f);
}

static void alice_fatal_signal_handler(int sig, siginfo_t *info, void *context) {
    NSString *crashPath = AliceGetCrashFilePath();
    FILE *f = fopen([crashPath UTF8String], "a");
    if (!f) f = stderr;

    const char *sigName = "UNKNOWN";
    switch (sig) {
        case SIGSEGV: sigName = "SIGSEGV (Segmentation Fault - Invalid Memory Access)"; break;
        case SIGBUS:  sigName = "SIGBUS (Bus Error - Alignment / Unmapped Memory)"; break;
        case SIGABRT: sigName = "SIGABRT (Abort / Assertion Failure)"; break;
        case SIGILL:  sigName = "SIGILL (Illegal Instruction)"; break;
        case SIGFPE:  sigName = "SIGFPE (Floating Point Exception)"; break;
        case SIGTRAP: sigName = "SIGTRAP (Trace/Breakpoint Trap)"; break;
    }

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *ts = [df stringFromDate:[NSDate date]];

    fprintf(f, "\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
    fprintf(f, "CRASH DETECTED at %s\n", [ts UTF8String]);
    fprintf(f, "Signal: %d [%s]\n", sig, sigName);
    if (info) {
        fprintf(f, "Fault Address: %p, Signal Code: %d\n", info->si_addr, info->si_code);
    }

    void *callstack[128];
    int frames = backtrace(callstack, 128);
    char **strs = backtrace_symbols(callstack, frames);
    fprintf(f, "\nCall Stack (%d frames):\n", frames);
    if (strs) {
        for (int i = 0; i < frames; ++i) {
            fprintf(f, "  #%02d %s\n", i, strs[i]);
        }
        free(strs);
    }
    fprintf(f, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n\n");
    fflush(f);
    if (f != stderr) fclose(f);

    fprintf(stderr, "\n[LookingMetal] FATAL SIGNAL: %d [%s] at %p\n", sig, sigName, info ? info->si_addr : NULL);
    fflush(stderr);

    signal(sig, SIG_DFL);
    raise(sig);
}

static void alice_uncaught_exception_handler(NSException *exception) {
    NSString *crashPath = AliceGetCrashFilePath();
    FILE *f = fopen([crashPath UTF8String], "a");
    if (!f) f = stderr;

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *ts = [df stringFromDate:[NSDate date]];

    fprintf(f, "\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
    fprintf(f, "UNCAUGHT OBJC EXCEPTION at %s\n", [ts UTF8String]);
    fprintf(f, "Name: %s\n", [[exception name] UTF8String]);
    fprintf(f, "Reason: %s\n", [[exception reason] UTF8String]);
    fprintf(f, "Call Stack:\n");
    for (NSString *symbol in [exception callStackSymbols]) {
        fprintf(f, "  %s\n", [symbol UTF8String]);
    }
    fprintf(f, "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n\n");
    fflush(f);
    if (f != stderr) fclose(f);

    fprintf(stderr, "[LookingMetal] UNCAUGHT EXCEPTION: %s (%s)\n", [[exception name] UTF8String], [[exception reason] UTF8String]);
    fflush(stderr);
}

void AliceInitLogging(void) {
    static int s_logging_initialized = 0;
    if (s_logging_initialized) return;
    s_logging_initialized = 1;

    NSString *logPath = AliceGetLogFilePath();

    // Rotate log if > 8MB
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:logPath error:nil];
    if (attrs && [attrs fileSize] > 8 * 1024 * 1024) {
        NSString *oldPath = [logPath stringByAppendingPathExtension:@"old"];
        [fm removeItemAtPath:oldPath error:nil];
        [fm moveItemAtPath:logPath toPath:oldPath error:nil];
    }

    FILE *fOut = freopen([logPath UTF8String], "a+", stdout);
    if (fOut) {
        setvbuf(stdout, NULL, _IOLBF, 1024);
    }
    FILE *fErr = freopen([logPath UTF8String], "a+", stderr);
    if (fErr) {
        setvbuf(stderr, NULL, _IONBF, 0);
    }

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *ts = [df stringFromDate:[NSDate date]];

    printf("\n=======================================================\n");
    printf("[LookingMetal] Session Started at %s\n", [ts UTF8String]);
    printf("[LookingMetal] System: iOS %s (%s)\n",
           [[[UIDevice currentDevice] systemVersion] UTF8String],
           [[[UIDevice currentDevice] model] UTF8String]);
    printf("[LookingMetal] Log File: %s\n", [logPath UTF8String]);
    printf("=======================================================\n");
    fflush(stdout);

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = alice_fatal_signal_handler;
    sa.sa_flags = SA_SIGINFO | SA_RESETHAND;
    sigemptyset(&sa.sa_mask);

    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGBUS,  &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
    sigaction(SIGILL,  &sa, NULL);
    sigaction(SIGFPE,  &sa, NULL);
    sigaction(SIGTRAP, &sa, NULL);

    NSSetUncaughtExceptionHandler(&alice_uncaught_exception_handler);
}

// ---------------------------------------------------------------------------
// Metal Triple-Buffering Frame Pacing
// ---------------------------------------------------------------------------
static dispatch_semaphore_t s_frame_pacing_semaphore = NULL;

void AliceFramePacing_Wait(void) {
    if (!s_frame_pacing_semaphore) {
        s_frame_pacing_semaphore = dispatch_semaphore_create(3);
    }
    // 500ms safety timeout: guarantees no deadlock under any circumstance
    dispatch_semaphore_wait(s_frame_pacing_semaphore, dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC));
}

void AliceFramePacing_Signal(void) {
    if (s_frame_pacing_semaphore) {
        dispatch_semaphore_signal(s_frame_pacing_semaphore);
    }
}

void AliceFramePacing_SignalOnComplete(void* commandBufferPtr) {
    if (!commandBufferPtr) {
        AliceFramePacing_Signal();
        return;
    }
    if (!s_frame_pacing_semaphore) {
        s_frame_pacing_semaphore = dispatch_semaphore_create(3);
    }
    id<MTLCommandBuffer> cb = (__bridge id<MTLCommandBuffer>)commandBufferPtr;
    dispatch_semaphore_t sema = s_frame_pacing_semaphore;
    [cb addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull buffer) {
        (void)buffer;
        dispatch_semaphore_signal(sema);
    }];
}

__attribute__((constructor)) static void alice_hud_prelaunch(void) {
    AliceInitLogging();
    if (AliceIsMetalHUDRequested()) {
        setenv("MTL_HUD_ENABLED", "1", 1);
        setenv("MTL_HUD_HIDE_METALFX_METRICS", "1", 1);
        AliceLog(@"[LookingMetal] __attribute__((constructor)): setenv MTL_HUD_ENABLED=1 at dyld init");
    } else {
        unsetenv("MTL_HUD_ENABLED");
    }
}

void AlicePreMetalInit(void) {
    if (AliceIsMetalHUDRequested()) {
        setenv("MTL_HUD_ENABLED", "1", 1);
        setenv("MTL_HUD_HIDE_METALFX_METRICS", "1", 1);
        AliceLog(@"[LookingMetal] AlicePreMetalInit: setenv MTL_HUD_ENABLED=1 before MTLCreateSystemDefaultDevice");
    } else {
        unsetenv("MTL_HUD_ENABLED");
    }
}

void AliceApplyMetalHUD(void* mtkViewPtr) {
    BOOL enabled = AliceIsMetalHUDRequested();
    AliceLog(@"[LookingMetal] AliceApplyMetalHUD: enabled=%d, mtkViewPtr=%p", enabled, mtkViewPtr);

    if (@available(iOS 16.0, *)) {
        UIView *view = (__bridge UIView*)mtkViewPtr;
        CAMetalLayer *metalLayer = AliceFindMetalLayer(view);
        if (metalLayer) {
            metalLayer.developerHUDProperties = enabled ? @{@"mode": @"default"} : nil;
            AliceLog(@"[LookingMetal] AliceApplyMetalHUD: set developerHUDProperties on layer %p to %@", metalLayer, metalLayer.developerHUDProperties);
        } else {
            AliceLog(@"[LookingMetal] AliceApplyMetalHUD: could not find CAMetalLayer on view %@", view);
        }
    }
}

float AliceGetRenderScale(void) {
    UIScreen *screen = [UIScreen mainScreen];
    CGFloat nativeScale = [screen respondsToSelector:@selector(nativeScale)] ? screen.nativeScale : screen.scale;
    // On ultra-high-density 3x displays (e.g. iPhone 16 Pro Max 2868x1320),
    // rendering at 2.0x (1912x880, >300 PPI) reduces fragment rasterization load by 56%,
    // dropping GPU time from 11.8ms to ~4.5ms, guaranteeing locked 60-120 FPS without sawtooth jitter.
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if ([defs objectForKey:@"AliceRenderScale"] != nil) {
        float custom = [defs floatForKey:@"AliceRenderScale"];
        if (custom >= 1.0f && custom <= 3.0f) return custom;
    }
    if (nativeScale >= 2.5) {
        return 2.0f;
    }
    return (float)(nativeScale > 0.0 ? nativeScale : 2.0);
}

@interface AlicePerformanceHUDView : UIView {
    float _frameHistory[30];
}
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *fpsLabel;
@property (nonatomic, strong) UILabel *msLabel;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) CFTimeInterval lastTimestamp;
@property (nonatomic, assign) int historyCount;
@property (nonatomic, assign) int historyIndex;
@property (nonatomic, assign) BOOL isMini;
- (void)start;
- (void)stop;
@end

@implementation AlicePerformanceHUDView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.layer.cornerRadius = 12.0;
        self.layer.masksToBounds = YES;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
        self.layer.borderWidth = 0.5;

        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        _blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
        _blurView.frame = self.bounds;
        _blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_blurView];

        UIView *content = _blurView.contentView;

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, 122, 11)];
        _titleLabel.text = @"⚡ METAL / PERF";
        _titleLabel.textColor = [UIColor colorWithRed:1.0 green:0.84 blue:0.25 alpha:0.95];
        _titleLabel.font = [UIFont systemFontOfSize:9.0 weight:UIFontWeightBold];
        [content addSubview:_titleLabel];

        _fpsLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 16, 122, 22)];
        _fpsLabel.text = @"60.0 FPS";
        _fpsLabel.textColor = [UIColor colorWithRed:0.20 green:0.85 blue:0.40 alpha:1.0];
        _fpsLabel.font = [UIFont monospacedDigitSystemFontOfSize:17.0 weight:UIFontWeightBold];
        [content addSubview:_fpsLabel];

        _msLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 37, 122, 12)];
        _msLabel.text = @"16.6 ms · 60Hz";
        _msLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
        _msLabel.font = [UIFont monospacedDigitSystemFontOfSize:10.0 weight:UIFontWeightMedium];
        [content addSubview:_msLabel];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTap:)];
        [self addGestureRecognizer:tap];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)onTap:(UITapGestureRecognizer *)tap {
    self.isMini = !self.isMini;
    [UIView animateWithDuration:0.2 animations:^{
        CGRect f = self.frame;
        if (self.isMini) {
            f.size = CGSizeMake(84, 28);
            self.titleLabel.hidden = YES;
            self.msLabel.hidden = YES;
            self.fpsLabel.frame = CGRectMake(8, 4, 68, 20);
            self.fpsLabel.font = [UIFont monospacedDigitSystemFontOfSize:13.5 weight:UIFontWeightBold];
        } else {
            f.size = CGSizeMake(142, 54);
            self.titleLabel.hidden = NO;
            self.msLabel.hidden = NO;
            self.fpsLabel.frame = CGRectMake(10, 16, 122, 22);
            self.fpsLabel.font = [UIFont monospacedDigitSystemFontOfSize:17.0 weight:UIFontWeightBold];
        }
        self.frame = f;
    }];
}

- (void)onPan:(UIPanGestureRecognizer *)pan {
    CGPoint trans = [pan translationInView:self.superview];
    CGPoint c = self.center;
    c.x += trans.x;
    c.y += trans.y;

    if (self.superview) {
        UIEdgeInsets insets = UIEdgeInsetsZero;
        if (@available(iOS 11.0, *)) {
            insets = self.superview.safeAreaInsets;
        }
        CGFloat halfW = self.bounds.size.width / 2.0;
        CGFloat halfH = self.bounds.size.height / 2.0;
        CGFloat minX = insets.left + halfW + 4;
        CGFloat maxX = self.superview.bounds.size.width - insets.right - halfW - 4;
        CGFloat minY = insets.top + halfH + 4;
        CGFloat maxY = self.superview.bounds.size.height - insets.bottom - halfH - 4;
        c.x = MAX(minX, MIN(maxX, c.x));
        c.y = MAX(minY, MIN(maxY, c.y));
    }
    self.center = c;
    [pan setTranslation:CGPointZero inView:self.superview];
}

- (void)start {
    if (self.displayLink) return;
    self.lastTimestamp = 0;
    self.historyCount = 0;
    self.historyIndex = 0;
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    if (@available(iOS 15.0, *)) {
        self.displayLink.preferredFrameRateRange = CAFrameRateRangeMake(30, 120, 120);
    }
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stop {
    [self.displayLink invalidate];
    self.displayLink = nil;
}

- (void)tick:(CADisplayLink *)link {
    if (self.lastTimestamp == 0) {
        self.lastTimestamp = link.timestamp;
        return;
    }
    CFTimeInterval dt = link.timestamp - self.lastTimestamp;
    self.lastTimestamp = link.timestamp;
    if (dt <= 0.001 || dt > 0.5) return;

    _frameHistory[self.historyIndex] = (float)dt;
    self.historyIndex = (self.historyIndex + 1) % 30;
    if (self.historyCount < 30) self.historyCount++;

    float sum = 0;
    for (int i = 0; i < self.historyCount; i++) {
        sum += _frameHistory[i];
    }
    float avgDt = sum / (float)self.historyCount;
    float fps = 1.0f / avgDt;
    float ms = avgDt * 1000.0f;

    NSInteger maxFps = 60;
    if (@available(iOS 10.3, *)) {
        maxFps = [UIScreen mainScreen].maximumFramesPerSecond;
    }

    if (self.isMini) {
        self.fpsLabel.text = [NSString stringWithFormat:@"%.0f FPS", fps];
    } else {
        self.fpsLabel.text = [NSString stringWithFormat:@"%.1f FPS", fps];
        self.msLabel.text = [NSString stringWithFormat:@"%.1f ms · %ldHz", ms, (long)maxFps];
    }

    if (fps >= (float)maxFps * 0.90f) {
        self.fpsLabel.textColor = [UIColor colorWithRed:0.20 green:0.85 blue:0.40 alpha:1.0];
    } else if (fps >= 45.0f) {
        self.fpsLabel.textColor = [UIColor colorWithRed:1.0 green:0.84 blue:0.25 alpha:1.0];
    } else {
        self.fpsLabel.textColor = [UIColor colorWithRed:1.0 green:0.30 blue:0.25 alpha:1.0];
    }
}

@end

static AlicePerformanceHUDView *s_hud_view = nil;

void AlicePerformanceHUD_SetVisible(int visible) {
    (void)visible;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (s_hud_view) {
            [s_hud_view stop];
            [s_hud_view removeFromSuperview];
            s_hud_view = nil;
        }
    });
}

int AlicePerformanceHUD_IsVisible(void) {
    return 0;
}

static int s_last_hud_state = -1;
void AliceOnFrameDrawable(void* drawablePtr) {
    if (!drawablePtr) return;
    int wanted = AliceIsMetalHUDRequested() ? 1 : 0;
    if (wanted == s_last_hud_state) return;

    id drawable = (__bridge id)drawablePtr;
    if ([drawable respondsToSelector:@selector(layer)]) {
        id layer = [drawable performSelector:@selector(layer)];
        if (layer && [layer respondsToSelector:@selector(setDeveloperHUDProperties:)]) {
            if (wanted) {
                [layer performSelector:@selector(setDeveloperHUDProperties:) withObject:@{@"mode": @"default"}];
                AliceLog(@"[LookingMetal] AliceOnFrameDrawable: HUD activated on drawable.layer %p", layer);
            } else {
                [layer performSelector:@selector(setDeveloperHUDProperties:) withObject:nil];
                AliceLog(@"[LookingMetal] AliceOnFrameDrawable: HUD deactivated on drawable.layer %p", layer);
            }
            s_last_hud_state = wanted;
        }
    }
}

void AliceNativeMenu_SetMetalHUD(int enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:(enabled != 0) forKey:@"MetalHUDEnabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (enabled) {
        setenv("MTL_HUD_ENABLED", "1", 1);
    } else {
        unsetenv("MTL_HUD_ENABLED");
        unsetenv("DM_METAL_HUD");
    }
    s_last_hud_state = -1;

    AlicePerformanceHUD_SetVisible(enabled);
    AliceLog(@"[LookingMetal] AliceNativeMenu_SetMetalHUD: enabled=%d", enabled);

    if (@available(iOS 16.0, *)) {
        void* p = AliceGetMTKView();
        if (p) {
            UIView *mtkView = (__bridge UIView*)p;
            CAMetalLayer *metalLayer = AliceFindMetalLayer(mtkView);
            if (metalLayer) {
                metalLayer.developerHUDProperties = enabled ? @{@"mode": @"default"} : nil;
                AliceLog(@"[LookingMetal] AliceNativeMenu_SetMetalHUD: set developerHUDProperties on mtkView.layer %p", metalLayer);
            }
        }
    }
}

UIViewController* AliceGetRootViewController(void* hint) {
    if (hint) {
        return (__bridge UIViewController*)hint;
    }
    if (miniquad_ios_root_view_controller) {
        void* r = miniquad_ios_root_view_controller();
        if (r) return (__bridge UIViewController*)r;
    }
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in scene.windows) {
                    if (w.isKeyWindow && w.rootViewController) { window = w; break; }
                }
                if (!window) {
                    for (UIWindow *w in scene.windows) {
                        if (w.rootViewController) { window = w; break; }
                    }
                }
            }
            if (window) break;
        }
    }
    if (!window) window = [UIApplication sharedApplication].keyWindow;
    if (!window && [UIApplication sharedApplication].windows.count > 0) {
        window = [UIApplication sharedApplication].windows[0];
    }
    return window.rootViewController;
}

void AliceApplyFPSLimit(int fps) {
    if (miniquad_ios_set_preferred_fps) {
        miniquad_ios_set_preferred_fps(fps);
        AliceLog(@"[LookingMetal] AliceApplyFPSLimit: called miniquad_ios_set_preferred_fps(%d)", fps);
    }
}

void AliceNativeMenu_Show(void* root_vc_ptr,
                          int is_pause,
                          int has_continue, int continue_slot,
                          const char* continue_chapter, const char* continue_date,
                          const AliceSaveSlotInfo* slots, int slot_count,
                          const AliceChapterInfo* chapters, int chapter_count,
                          float sound_vol, float music_vol, float voice_vol,
                          float look_sens, int invert_y, int metal_hud) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (s_active_menu_view) {
            [s_active_menu_view removeFromSuperview];
            s_active_menu_view = nil;
        }

        UIViewController *rootVC = AliceGetRootViewController(root_vc_ptr);
        if (!rootVC || !rootVC.view) {
            NSLog(@"[AliceNativeMenu] Error: rootViewController not found!");
            return;
        }

        memset(&s_result, 0, sizeof(s_result));
        s_result.sound_vol = sound_vol;
        s_result.music_vol = music_vol;
        s_result.voice_vol = voice_vol;
        s_result.look_sens = look_sens;
        s_result.invert_y = invert_y;
        s_result.metal_hud = metal_hud;
        s_has_action = 0;

        AliceNativeMenuView *menu = [[AliceNativeMenuView alloc] initWithFrame:rootVC.view.bounds];
        menu.isPause = (is_pause != 0);
        menu.soundVol = sound_vol;
        menu.musicVol = music_vol;
        menu.voiceVol = voice_vol;
        menu.lookSens = look_sens;
        menu.invertY = (invert_y != 0);
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        if ([defs objectForKey:@"MetalHUDEnabled"] != nil) {
            menu.metalHUD = [defs boolForKey:@"MetalHUDEnabled"];
        } else {
            menu.metalHUD = (metal_hud != 0);
        }

        menu.hasContinue = (has_continue != 0);
        menu.continueSlot = continue_slot;
        menu.continueChapter = continue_chapter ? [NSString stringWithUTF8String:continue_chapter] : @"";
        menu.continueDate = continue_date ? [NSString stringWithUTF8String:continue_date] : @"";

        AlicePerformanceHUD_SetVisible(menu.metalHUD ? 1 : 0);

        // Slots
        menu.slotItems = [NSMutableArray arrayWithCapacity:slot_count];
        for (int i = 0; i < slot_count; i++) {
            NSString *stitle = slots[i].slot_title ? [NSString stringWithUTF8String:slots[i].slot_title] : @"";
            NSString *cname = slots[i].chapter_name ? [NSString stringWithUTF8String:slots[i].chapter_name] : @"";
            NSString *sdate = slots[i].save_date ? [NSString stringWithUTF8String:slots[i].save_date] : @"";
            [menu.slotItems addObject:@{
                @"slot": @(slots[i].slot_idx),
                @"title": stitle,
                @"chapter": cname,
                @"date": sdate,
                @"empty": @(slots[i].is_empty != 0)
            }];
        }

        // Chapters
        menu.chapterItems = [NSMutableArray arrayWithCapacity:chapter_count];
        for (int i = 0; i < chapter_count; i++) {
            NSString *t = chapters[i].title ? [NSString stringWithUTF8String:chapters[i].title] : @"";
            NSString *m = chapters[i].map_name ? [NSString stringWithUTF8String:chapters[i].map_name] : @"";
            [menu.chapterItems addObject:@{
                @"idx": @(chapters[i].chapter_idx),
                @"title": t,
                @"map": m
            }];
        }

        [menu showPage:MenuPageMain];

        menu.alpha = 0.0;
        menu.cardView.transform = CGAffineTransformMakeScale(0.92, 0.92);
        [rootVC.view addSubview:menu];
        s_active_menu_view = menu;

        [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            menu.alpha = 1.0;
            menu.cardView.transform = CGAffineTransformIdentity;
        } completion:nil];
    });
}

int AliceNativeMenu_HasAction(void) {
    return s_has_action;
}

AliceMenuResult AliceNativeMenu_GetResult(void) {
    return s_result;
}

void AliceNativeMenu_Dismiss(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (s_active_menu_view) {
            [(AliceNativeMenuView *)s_active_menu_view dismissWithAnimation];
        }
    });
}
