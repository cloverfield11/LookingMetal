#pragma once
#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    AliceMenuActionNone = 0,
    AliceMenuActionNewGame = 1,
    AliceMenuActionLoadGame = 2,
    AliceMenuActionChapters = 3,
    AliceMenuActionSettings = 4,
    AliceMenuActionQuit = 5,
    AliceMenuActionContinue = 6, // Resume in pause menu
    AliceMenuActionSave = 7,     // Save game in pause menu
} AliceMenuAction;

typedef struct {
    int action;       // AliceMenuAction
    int difficulty;   // 0 = Easy, 1 = Normal, 2 = Hard
    int save_slot;    // 0 = Slot 1, 1 = Slot 2, 2 = Slot 3, 3 = Slot 4, 4 = Quick, 5 = Auto
    int chapter_idx;  // Map index
    float sound_vol;
    float music_vol;
    float voice_vol;
    float look_sens;
    int invert_y;
    int metal_hud;
} AliceMenuResult;

typedef struct {
    int slot_idx;
    const char* slot_title;
    const char* chapter_name;
    const char* save_date;
    int is_empty;
} AliceSaveSlotInfo;

typedef struct {
    int chapter_idx;
    const char* title;
    const char* map_name;
} AliceChapterInfo;

void AliceNativeMenu_Show(void* root_vc_ptr,
                          int is_pause,
                          int has_continue, int continue_slot,
                          const char* continue_chapter, const char* continue_date,
                          const AliceSaveSlotInfo* slots, int slot_count,
                          const AliceChapterInfo* chapters, int chapter_count,
                          float sound_vol, float music_vol, float voice_vol,
                          float look_sens, int invert_y, int metal_hud);

int AliceNativeMenu_HasAction(void);
AliceMenuResult AliceNativeMenu_GetResult(void);
void AliceNativeMenu_Dismiss(void);
void AliceNativeMenu_SetMetalHUD(int enabled);
void AlicePerformanceHUD_SetVisible(int visible);
int AlicePerformanceHUD_IsVisible(void);
void AlicePreMetalInit(void);
void AliceApplyMetalHUD(void* mtkViewPtr);
void AliceOnFrameDrawable(void* drawablePtr);

#ifdef __cplusplus
}
#endif
