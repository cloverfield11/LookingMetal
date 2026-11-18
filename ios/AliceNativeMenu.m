#import "AliceNativeMenu.h"

// Forward declaration if miniquad exports it
extern void* miniquad_ios_root_view_controller(void) __attribute__((weak));

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
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *pageContainer;

// State data
@property (nonatomic, assign) MenuPage currentPage;
@property (nonatomic, strong) NSMutableArray<NSDictionary*> *slotItems;
@property (nonatomic, strong) NSMutableArray<NSDictionary*> *chapterItems;
@property (nonatomic, assign) float soundVol;
@property (nonatomic, assign) float musicVol;
@property (nonatomic, assign) float voiceVol;
@property (nonatomic, assign) float lookSens;
@property (nonatomic, assign) BOOL invertY;

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
    // 1. Frosted Glass Backdrop
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    self.blurView.frame = self.bounds;
    self.blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:self.blurView];

    // Dark tint overlay for atmospheric gothic depth
    UIView *tintView = [[UIView alloc] initWithFrame:self.bounds];
    tintView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tintView.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:0.65];
    [self.blurView.contentView addSubview:tintView];

    // 2. Centered Floating Card
    self.cardView = [[UIView alloc] init];
    self.cardView.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.75];
    self.cardView.layer.cornerRadius = 24.0;
    if (@available(iOS 13.0, *)) {
        self.cardView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.cardView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    self.cardView.layer.borderWidth = 1.2;
    self.cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.cardView.layer.shadowOpacity = 0.55;
    self.cardView.layer.shadowRadius = 24.0;
    self.cardView.layer.shadowOffset = CGSizeMake(0, 10);
    [self addSubview:self.cardView];

    // 3. Header
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = @"AMERICAN MCGEE'S ALICE";
    self.titleLabel.textColor = [UIColor colorWithRed:0.95 green:0.92 blue:0.86 alpha:1.0];
    self.titleLabel.font = [UIFont fontWithName:@"Georgia-Bold" size:22.0] ?: [UIFont boldSystemFontOfSize:22.0];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.cardView addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.text = @"LOOKINGMETAL · APPLE METAL 3 · 120 FPS";
    self.subtitleLabel.textColor = [UIColor colorWithWhite:0.70 alpha:1.0];
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
    [self updateLayout];
}

- (void)updateLayout {
    CGSize sz = self.bounds.size;
    CGFloat cardW = MIN(sz.width - 32.0, 520.0);
    CGFloat cardH = MIN(sz.height - 32.0, 360.0);
    CGFloat cardX = (sz.width - cardW) * 0.5;
    CGFloat cardY = (sz.height - cardH) * 0.5;

    self.cardView.frame = CGRectMake(cardX, cardY, cardW, cardH);
    self.titleLabel.frame = CGRectMake(16.0, 16.0, cardW - 32.0, 26.0);
    self.subtitleLabel.frame = CGRectMake(16.0, 42.0, cardW - 32.0, 16.0);

    CGFloat contentY = 66.0;
    self.pageContainer.frame = CGRectMake(16.0, contentY, cardW - 32.0, cardH - contentY - 16.0);
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
    transition.duration = 0.22;
    transition.type = kCATransitionFade;
    [self.pageContainer.layer addAnimation:transition forKey:nil];
}

#pragma mark - Button Helper

- (UIButton *)createButtonWithTitle:(NSString *)title icon:(NSString *)icon tag:(NSInteger)tag action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.tag = tag;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    btn.layer.cornerRadius = 14.0;
    if (@available(iOS 13.0, *)) {
        btn.layer.cornerCurve = kCACornerCurveContinuous;
    }
    btn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
    btn.layer.borderWidth = 1.0;

    NSString *fullText = icon ? [NSString stringWithFormat:@"%@  %@", icon, title] : title;
    [btn setTitle:fullText forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor colorWithWhite:0.95 alpha:1.0] forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor colorWithWhite:0.60 alpha:1.0] forState:UIControlStateHighlighted];
    btn.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];

    return btn;
}

#pragma mark - Page 0: Main Menu

- (void)buildMainPage {
    CGSize size = self.pageContainer.bounds.size;
    CGFloat btnW = size.width;
    CGFloat btnH = 44.0;
    CGFloat spacing = 8.0;

    NSArray *items = @[
        @{@"t": @"Новая игра (New Game)", @"i": @"⚔️", @"tag": @1},
        @{@"t": @"Загрузить (Load Game)", @"i": @"💾", @"tag": @2},
        @{@"t": @"Выбор главы (Chapters)", @"i": @"📖", @"tag": @3},
        @{@"t": @"Настройки (Settings)", @"i": @"⚙️", @"tag": @4},
        @{@"t": @"Выход в лаунчер (Quit)", @"i": @"🚪", @"tag": @5},
    ];

    CGFloat totalH = items.count * btnH + (items.count - 1) * spacing;
    CGFloat startY = MAX(0.0, (size.height - totalH) * 0.5);

    NSUInteger count = items.count;
    for (NSUInteger i = 0; i < count; i++) {
        NSDictionary *dict = items[i];
        UIButton *btn = [self createButtonWithTitle:dict[@"t"]
                                               icon:dict[@"i"]
                                                tag:[dict[@"tag"] integerValue]
                                             action:@selector(onMainMenuTap:)];
        btn.frame = CGRectMake(0, startY + i * (btnH + spacing), btnW, btnH);
        [self.pageContainer addSubview:btn];
    }
}

- (void)onMainMenuTap:(UIButton *)btn {
    [self.haptic impactOccurred];
    switch (btn.tag) {
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

    UIButton *backBtn = [self createButtonWithTitle:@"‹ Назад в меню" icon:nil tag:0 action:@selector(onBackTap:)];
    backBtn.frame = CGRectMake(0, 0, 140.0, 34.0);
    backBtn.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    [self.pageContainer addSubview:backBtn];

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(148.0, 0, size.width - 148.0, 34.0)];
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
    CGFloat startY = 44.0;

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

    UIButton *backBtn = [self createButtonWithTitle:@"‹ Назад в меню" icon:nil tag:0 action:@selector(onBackTap:)];
    backBtn.frame = CGRectMake(0, 0, 140.0, 34.0);
    backBtn.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    [self.pageContainer addSubview:backBtn];

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(148.0, 0, size.width - 148.0, 34.0)];
    header.text = @"СОХРАНЕНИЯ (LOAD GAME)";
    header.textColor = [UIColor colorWithRed:0.95 green:0.85 blue:0.65 alpha:1.0];
    header.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    header.textAlignment = NSTextAlignmentRight;
    [self.pageContainer addSubview:header];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 42.0, size.width, size.height - 42.0)];
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

    UIButton *backBtn = [self createButtonWithTitle:@"‹ Назад в меню" icon:nil tag:0 action:@selector(onBackTap:)];
    backBtn.frame = CGRectMake(0, 0, 140.0, 34.0);
    backBtn.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    [self.pageContainer addSubview:backBtn];

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(148.0, 0, size.width - 148.0, 34.0)];
    header.text = @"ГЛАВЫ (CHAPTERS)";
    header.textColor = [UIColor colorWithRed:0.95 green:0.85 blue:0.65 alpha:1.0];
    header.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    header.textAlignment = NSTextAlignmentRight;
    [self.pageContainer addSubview:header];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 42.0, size.width, size.height - 42.0)];
    scroll.showsVerticalScrollIndicator = YES;
    [self.pageContainer addSubview:scroll];

    CGFloat btnH = 42.0;
    CGFloat spacing = 6.0;

    NSUInteger chapCount = self.chapterItems.count;
    for (NSUInteger i = 0; i < chapCount; i++) {
        NSDictionary *c = self.chapterItems[i];
        UIButton *btn = [self createButtonWithTitle:c[@"title"]
                                               icon:@"📖"
                                                tag:[c[@"idx"] integerValue]
                                             action:@selector(onChapterSelect:)];
        btn.frame = CGRectMake(0, i * (btnH + spacing), size.width, btnH);
        btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
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

    UIButton *backBtn = [self createButtonWithTitle:@"‹ Назад в меню" icon:nil tag:0 action:@selector(onBackTap:)];
    backBtn.frame = CGRectMake(0, 0, 140.0, 34.0);
    backBtn.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    [self.pageContainer addSubview:backBtn];

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(148.0, 0, size.width - 148.0, 34.0)];
    header.text = @"НАСТРОЙКИ (SETTINGS)";
    header.textColor = [UIColor colorWithRed:0.95 green:0.85 blue:0.65 alpha:1.0];
    header.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    header.textAlignment = NSTextAlignmentRight;
    [self.pageContainer addSubview:header];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 40.0, size.width, size.height - 40.0)];
    scroll.showsVerticalScrollIndicator = YES;
    [self.pageContainer addSubview:scroll];

    CGFloat rowH = 44.0;
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
    tl.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    [toggleRow addSubview:tl];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(size.width - 55, 6, 51, 31)];
    sw.on = self.invertY;
    sw.onTintColor = [UIColor colorWithRed:0.85 green:0.25 blue:0.25 alpha:1.0];
    [sw addTarget:self action:@selector(onInvertYToggle:) forControlEvents:UIControlEventValueChanged];
    [toggleRow addSubview:sw];
    [scroll addSubview:toggleRow];
    y += rowH;

    scroll.contentSize = CGSizeMake(size.width, y + 10.0);
}

- (void)addSliderTo:(UIView *)parent y:(CGFloat)y label:(NSString *)label val:(float)val min:(float)min max:(float)max tag:(NSInteger)tag action:(SEL)act {
    CGFloat w = parent.bounds.size.width;
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, w, 44.0)];

    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(4, 0, w * 0.45, 44.0)];
    l.text = label;
    l.textColor = [UIColor whiteColor];
    l.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    [row addSubview:l];

    UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(w * 0.45 + 10, 6, w * 0.55 - 14, 32.0)];
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

- (void)onBackTap:(UIButton *)btn {
    [self.haptic impactOccurred];
    [self showPage:MenuPageMain];
}

- (void)dismissWithAnimation {
    [UIView animateWithDuration:0.25 animations:^{
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
                    if (w.isKeyWindow) { window = w; break; }
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

void AliceNativeMenu_Show(void* root_vc_ptr,
                          const AliceSaveSlotInfo* slots, int slot_count,
                          const AliceChapterInfo* chapters, int chapter_count,
                          float sound_vol, float music_vol, float voice_vol,
                          float look_sens, int invert_y) {
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
        s_has_action = 0;

        AliceNativeMenuView *menu = [[AliceNativeMenuView alloc] initWithFrame:rootVC.view.bounds];
        menu.soundVol = sound_vol;
        menu.musicVol = music_vol;
        menu.voiceVol = voice_vol;
        menu.lookSens = look_sens;
        menu.invertY = (invert_y != 0);

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

        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
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
