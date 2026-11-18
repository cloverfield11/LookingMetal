#import "AliceNativeMenu.h"
#import <QuartzCore/QuartzCore.h>

// Forward declarations from miniquad
extern void* miniquad_ios_root_view_controller(void) __attribute__((weak));
extern void* miniquad_ios_mtk_view(void) __attribute__((weak));
extern void miniquad_ios_set_preferred_fps(int fps) __attribute__((weak));

static AliceMenuResult s_result = {0};
static int s_has_action = 0;
static UIView *s_active_menu_view = nil;

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
@property (nonatomic, assign) int fpsChoice;
@property (nonatomic, assign) int touchScale;

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
        self.titleLabel.text = @"ПАУЗА";
        if (self.continueChapter && self.continueChapter.length > 0) {
            self.subtitleLabel.text = self.continueChapter;
        } else {
            self.subtitleLabel.text = @"ИГРА ПРИОСТАНОВЛЕНА";
        }
        self.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.06 alpha:0.80];

        [items addObject:@{@"t": @"Возобновить (Resume)", @"i": @"▶️", @"tag": @6, @"highlight": @YES}];
        [items addObject:@{@"t": @"Быстрое сохранение (Save)", @"i": @"💾", @"tag": @7, @"sub": @"Сохранить игру в Слот 1"}];
        [items addObject:@{@"t": @"Загрузить сохранение (Load)", @"i": @"📂", @"tag": @2}];
        [items addObject:@{@"t": @"Выбор главы (Chapters)", @"i": @"📖", @"tag": @3}];
        [items addObject:@{@"t": @"Настройки (Settings)", @"i": @"⚙️", @"tag": @4}];
        [items addObject:@{@"t": @"Главное меню (Quit to Menu)", @"i": @"🚪", @"tag": @5}];
    } else {
        self.titleLabel.text = @"AMERICAN McGEE'S ALICE";
        self.subtitleLabel.text = @"LOOKINGMETAL · iOS NATIVE EDITION";
        self.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.06 alpha:1.0];

        if (self.hasContinue) {
            NSString *sub = [NSString stringWithFormat:@"%@  ·  %@", self.continueChapter ?: @"", self.continueDate ?: @""];
            [items addObject:@{@"t": @"Продолжить (Continue)", @"sub": sub, @"i": @"▶️", @"tag": @6, @"highlight": @YES}];
        }
        [items addObject:@{@"t": @"Новая игра (New Game)", @"i": @"⚔️", @"tag": @1}];
        [items addObject:@{@"t": @"Загрузить (Load Game)", @"i": @"💾", @"tag": @2}];
        [items addObject:@{@"t": @"Выбор главы (Chapters)", @"i": @"📖", @"tag": @3}];
        [items addObject:@{@"t": @"Настройки (Settings)", @"i": @"⚙️", @"tag": @4}];
        [items addObject:@{@"t": @"Выход в лаунчер (Quit)", @"i": @"🚪", @"tag": @5}];
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
    [backBtn setTitle:@"‹ Назад в меню" forState:UIControlStateNormal];
    [backBtn setTitleColor:[UIColor colorWithWhite:0.90 alpha:1.0] forState:UIControlStateNormal];
    backBtn.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    [backBtn addTarget:self action:@selector(onBackTap:) forControlEvents:UIControlEventTouchUpInside];
    [self.pageContainer addSubview:backBtn];

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(148.0, 0, size.width - 148.0, 32.0)];
    header.text = @"ВЫБЕРИТЕ СЛОЖНОСТЬ";
    header.textColor = [UIColor colorWithRed:0.95 green:0.85 blue:0.65 alpha:1.0];
    header.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    header.textAlignment = NSTextAlignmentRight;
    [self.pageContainer addSubview:header];

    NSArray *diffs = @[
        @{@"t": @"Легко (Easy)", @"sub": @"Для тех, кто хочет наслаждаться сюжетом", @"d": @0, @"color": [UIColor colorWithRed:0.3 green:0.8 blue:0.4 alpha:0.18]},
        @{@"t": @"Нормально (Medium)", @"sub": @"Классический баланс оригинальной игры 2000 г.", @"d": @1, @"color": [UIColor colorWithRed:0.9 green:0.7 blue:0.2 alpha:0.18]},
        @{@"t": @"Кошмар (Nightmare)", @"sub": @"Максимальный урон от кошмаров Страны Чудес", @"d": @2, @"color": [UIColor colorWithRed:0.9 green:0.25 blue:0.25 alpha:0.18]},
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
    [backBtn setTitle:@"‹ Назад в меню" forState:UIControlStateNormal];
    [backBtn setTitleColor:[UIColor colorWithWhite:0.90 alpha:1.0] forState:UIControlStateNormal];
    backBtn.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    [backBtn addTarget:self action:@selector(onBackTap:) forControlEvents:UIControlEventTouchUpInside];
    [self.pageContainer addSubview:backBtn];

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(148.0, 0, size.width - 148.0, 32.0)];
    header.text = @"ЗАГРУЗИТЬ СОХРАНЕНИЕ";
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
            slotTitle = [NSString stringWithFormat:@"Слот %lu", (unsigned long)(i + 1)];
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
            l.text = [NSString stringWithFormat:@"%@:  — Пустой —", slotTitle];
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

#pragma mark - Page 3: Chapters (Выбор главы)

- (void)buildChaptersPage {
    CGSize size = self.pageContainer.bounds.size;

    UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    backBtn.frame = CGRectMake(0, 0, 140.0, 32.0);
    [backBtn setTitle:@"‹ Назад в меню" forState:UIControlStateNormal];
    [backBtn setTitleColor:[UIColor colorWithWhite:0.90 alpha:1.0] forState:UIControlStateNormal];
    backBtn.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    [backBtn addTarget:self action:@selector(onBackTap:) forControlEvents:UIControlEventTouchUpInside];
    [self.pageContainer addSubview:backBtn];

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(148.0, 0, size.width - 148.0, 32.0)];
    header.text = @"ВЫБОР ГЛАВЫ";
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

#pragma mark - Page 4: Settings (Настройки)

- (void)buildSettingsPage {
    CGSize size = self.pageContainer.bounds.size;

    UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    backBtn.frame = CGRectMake(0, 0, 140.0, 32.0);
    [backBtn setTitle:@"‹ Назад в меню" forState:UIControlStateNormal];
    [backBtn setTitleColor:[UIColor colorWithWhite:0.90 alpha:1.0] forState:UIControlStateNormal];
    backBtn.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    [backBtn addTarget:self action:@selector(onBackTap:) forControlEvents:UIControlEventTouchUpInside];
    [self.pageContainer addSubview:backBtn];

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(148.0, 0, size.width - 148.0, 32.0)];
    header.text = @"НАСТРОЙКИ (SETTINGS)";
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
    [self addSliderTo:scroll y:y label:@"🔊 Звуковые эффекты" val:self.soundVol min:0 max:1 tag:101 action:@selector(onSliderChange:)];
    y += rowH;

    // 2. Music Vol
    [self addSliderTo:scroll y:y label:@"🎵 Музыка" val:self.musicVol min:0 max:1 tag:102 action:@selector(onSliderChange:)];
    y += rowH;

    // 3. Voice Vol
    [self addSliderTo:scroll y:y label:@"🎙️ Голос / Диалоги" val:self.voiceVol min:0 max:1 tag:103 action:@selector(onSliderChange:)];
    y += rowH;

    // 4. Look Sens
    [self addSliderTo:scroll y:y label:@"👁️ Чувствительность взгляда" val:self.lookSens min:0.5 max:3.0 tag:104 action:@selector(onSliderChange:)];
    y += rowH;

    // 5. Invert Y
    UIView *toggleRow = [[UIView alloc] initWithFrame:CGRectMake(0, y, size.width, rowH)];
    UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(4, 0, size.width - 70, rowH)];
    tl.text = @"↕️ Инвертировать ось Y камеры";
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
    hl.text = @"📊 Metal Performance HUD (FPS / GPU)";
    hl.textColor = [UIColor colorWithRed:0.70 green:0.95 blue:0.80 alpha:1.0];
    hl.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    [hudRow addSubview:hl];

    UILabel *subHl = [[UILabel alloc] initWithFrame:CGRectMake(4, 24, size.width - 70, 18)];
    subHl.text = @"Apple Metal 3 HUD · трекает кадры и GPU в реальном времени";
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

    // 7. FPS Lock (30 / 60 / 120)
    CGFloat fpsRowH = 54.0;
    UIView *fpsRow = [[UIView alloc] initWithFrame:CGRectMake(0, y, size.width, fpsRowH)];
    UILabel *fl = [[UILabel alloc] initWithFrame:CGRectMake(4, 2, size.width * 0.44, 22)];
    fl.text = @"⚡ Ограничение FPS (Lock)";
    fl.textColor = [UIColor colorWithRed:1.0 green:0.85 blue:0.40 alpha:1.0];
    fl.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightMedium];
    [fpsRow addSubview:fl];

    UILabel *subFl = [[UILabel alloc] initWithFrame:CGRectMake(4, 24, size.width * 0.44, 18)];
    subFl.text = @"30 (Эко) · 60 (Стабильно) · 120 (ProMotion)";
    subFl.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    subFl.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightRegular];
    [fpsRow addSubview:subFl];

    NSArray *fpsItems = @[@"30 FPS", @"60 FPS", @"120 FPS"];
    UISegmentedControl *fpsSeg = [[UISegmentedControl alloc] initWithItems:fpsItems];
    fpsSeg.frame = CGRectMake(size.width * 0.44 + 8, 8, size.width * 0.56 - 12, 32.0);
    int selectedFpsIdx = 1; // Default 60 FPS
    if (self.fpsChoice == 0) selectedFpsIdx = 0;
    else if (self.fpsChoice == 2) selectedFpsIdx = 2;
    else selectedFpsIdx = 1;
    fpsSeg.selectedSegmentIndex = selectedFpsIdx;
    [fpsSeg addTarget:self action:@selector(onFPSChange:) forControlEvents:UIControlEventValueChanged];
    [fpsRow addSubview:fpsSeg];
    [scroll addSubview:fpsRow];
    y += fpsRowH;

    // 8. Touch Controls Size (Размер экранных кнопок)
    CGFloat touchRowH = 54.0;
    UIView *touchRow = [[UIView alloc] initWithFrame:CGRectMake(0, y, size.width, touchRowH)];
    UILabel *touchL = [[UILabel alloc] initWithFrame:CGRectMake(4, 2, size.width * 0.44, 22)];
    touchL.text = @"🎮 Размер экранных кнопок";
    touchL.textColor = [UIColor whiteColor];
    touchL.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightMedium];
    [touchRow addSubview:touchL];

    UILabel *subTouchL = [[UILabel alloc] initWithFrame:CGRectMake(4, 24, size.width * 0.44, 18)];
    subTouchL.text = @"Компактные · Стандартные · Крупные";
    subTouchL.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    subTouchL.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightRegular];
    [touchRow addSubview:subTouchL];

    NSArray *touchItems = @[@"Мини", @"Норм", @"Макси"];
    UISegmentedControl *touchSeg = [[UISegmentedControl alloc] initWithItems:touchItems];
    touchSeg.frame = CGRectMake(size.width * 0.44 + 8, 8, size.width * 0.56 - 12, 32.0);
    int selectedTouchIdx = 0;
    if (self.touchScale == 1) selectedTouchIdx = 0; // Mini
    else if (self.touchScale == 2) selectedTouchIdx = 2; // Maxi
    else selectedTouchIdx = 1; // Norm
    touchSeg.selectedSegmentIndex = selectedTouchIdx;
    [touchSeg addTarget:self action:@selector(onTouchScaleChange:) forControlEvents:UIControlEventValueChanged];
    [touchRow addSubview:touchSeg];
    [scroll addSubview:touchRow];
    y += touchRowH;

    scroll.contentSize = CGSizeMake(size.width, y + 16.0);
}

- (void)onFPSChange:(UISegmentedControl *)seg {
    [self.haptic impactOccurred];
    int fps = 60;
    if (seg.selectedSegmentIndex == 0) {
        fps = 30;
        self.fpsChoice = 0;
    } else if (seg.selectedSegmentIndex == 2) {
        fps = 120;
        self.fpsChoice = 2;
    } else {
        fps = 60;
        self.fpsChoice = 1;
    }
    s_result.fps_choice = self.fpsChoice;
    AliceApplyFPSLimit(fps);
}

- (void)onTouchScaleChange:(UISegmentedControl *)seg {
    [self.haptic impactOccurred];
    if (seg.selectedSegmentIndex == 0) {
        self.touchScale = 1; // Mini
    } else if (seg.selectedSegmentIndex == 2) {
        self.touchScale = 2; // Maxi
    } else {
        self.touchScale = 0; // Norm
    }
    s_result.touch_scale = self.touchScale;
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
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"MetalHUDEnabled"]) {
        return YES;
    }
    NSDictionary *domain = [[NSUserDefaults standardUserDefaults] persistentDomainForName:@"org.lookingglass.alice"];
    if ([domain[@"MetalHUDEnabled"] boolValue]) {
        return YES;
    }
    const char *e = getenv("DM_METAL_HUD");
    if (e && atoi(e)) return YES;
    const char *m = getenv("MTL_HUD_ENABLED");
    if (m && atoi(m)) return YES;

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (paths.count > 0) {
        NSString *docDir = paths[0];
        NSString *launcherJson = [docDir stringByAppendingPathComponent:@"ios-launcher.json"];
        NSData *d = [NSData dataWithContentsOfFile:launcherJson];
        if (d) {
            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            if ([dict[@"metal_hud"] boolValue]) {
                return YES;
            }
        }
    }
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

__attribute__((constructor)) static void alice_hud_prelaunch(void) {
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
    setenv("MTL_HUD_ENABLED", enabled ? "1" : "0", 1);
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
                          float look_sens, int invert_y, int metal_hud,
                          int fps_choice, int touch_scale) {
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
        s_result.fps_choice = fps_choice;
        s_result.touch_scale = touch_scale;
        s_has_action = 0;

        AliceNativeMenuView *menu = [[AliceNativeMenuView alloc] initWithFrame:rootVC.view.bounds];
        menu.isPause = (is_pause != 0);
        menu.soundVol = sound_vol;
        menu.musicVol = music_vol;
        menu.voiceVol = voice_vol;
        menu.lookSens = look_sens;
        menu.invertY = (invert_y != 0);
        menu.fpsChoice = fps_choice;
        menu.touchScale = touch_scale;
        BOOL hudSaved = [[NSUserDefaults standardUserDefaults] boolForKey:@"MetalHUDEnabled"];
        menu.metalHUD = hudSaved || (metal_hud != 0);

        menu.hasContinue = (has_continue != 0);
        menu.continueSlot = continue_slot;
        menu.continueChapter = continue_chapter ? [NSString stringWithUTF8String:continue_chapter] : @"";
        menu.continueDate = continue_date ? [NSString stringWithUTF8String:continue_date] : @"";

        if (menu.metalHUD || AliceIsMetalHUDRequested()) {
            AlicePerformanceHUD_SetVisible(1);
        }

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
