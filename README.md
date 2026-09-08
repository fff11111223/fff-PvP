# fff PvP

《Warhammer: Vermintide 2》的休閒 PVP Mod。主要用途是在等待玩家、位於大廳或自訂娛樂場景時，暫時讓玩家可以互相進行近戰戰鬥；關閉 PVP 後，遊戲應恢復原生規則，不影響正常合作遊玩。

## 專案目標

- 儘量重用 VT2 原生的命中、格擋、fatigue、完美格擋、網路同步與玩家狀態流程。
- 只在 PVP 開關啟用時注入規則。
- 不依賴武器名稱白名單；武器分類使用原生 weapon template 的 `buff_type`。
- 讓 PVP 傷害、格擋消耗、卡刀與踉蹌規則可被清楚維護及測試。

## Build 與檔案結構

Build 入口是原生檔案：

```text
fff PvP.mod
resource_packages/fff PvP/fff PvP.package
scripts/mods/fff PvP/fff PvP.lua
scripts/mods/fff PvP/fff PvP_data.lua
scripts/mods/fff PvP/fff PvP_localization.lua
```

功能模組位於 `scripts/mods/pvp_mod/`，並由原生 `fff PvP.lua` 載入：

| 檔案 | 用途 |
|---|---|
| `pvp_damage.lua` | 友軍近戰命中、PVP 傷害倍率、PVP 格擋與武器碰撞 |
| `pvp_stagger.lua` | 完美格擋踉蹌、推擊踉蹌、受傷解除踉蹌 |
| `pvp_settings.lua` | UI 設定值讀取與倍率換算 |

## UI 設定

`fff PvP_data.lua` 提供兩個設定：

- `PVP Enabled`：預設開啟。關閉後所有 PVP Hook 放行原生函式，並清除現有 PVP 踉蹌。
- `PVP Damage (%)`：玩家對玩家傷害倍率，範圍 1%～200%，預設 25%。

啟用 PVP 後，Mod 會在聊天頻道逐行廣播完整規則。

## 函式用途

### `scripts/mods/fff PvP/fff PvP.lua`

- `get_mod("fff PvP")`：取得 VMF Mod 實例。
- `mod:dofile(path)`：載入 PVP 實作模組。
- `Damage.hook(mod, Settings)`：掛載近戰、傷害與格擋 Hook。
- `Stagger.hook(mod)`：掛載踉蹌與受傷解除 Hook。
- `mod.update()`：每幀呼叫 `Stagger.update(mod)`，處理踉蹌逾時或停用清理。
- `broadcast_pvp_rules()`：將目前 PVP 傷害倍率與完整規則送到聊天頻道；聊天不可用時改用 `mod:echo()`。
- `mod:on_setting_changed(callback)`：PVP 開關啟用時廣播規則，傷害倍率變更時顯示新倍率。

### `pvp_settings.lua`

- `is_enabled(mod)`：回傳 `pvp_enabled` 是否啟用。保留作為共用設定 API。
- `get_damage_multiplier(mod)`：讀取 `pvp_damage`，限制在 1～200 後轉成 `0.01`～`2.0` 倍率。

### `pvp_damage.lua`

- `enabled(mod)`：每個 Hook 的快速開關檢查；停用時直接呼叫原生函式。
- `attack_class(damage_profile)`：讀取 `damage_profile.charge_value`，轉換為 `light` 或 `heavy`。
- `weapon_class(unit)`：從 `weapon_system:get_weapon_template().buff_type` 取得 `MELEE_1H` 或 `MELEE_2H`。
- `current_attack_class(unit)`：讀取目標目前 `sweep`／`melee_start` 的 damage profile，判斷目標攻擊類型。
- `block_fatigue_type(attacker_unit, damage_profile)`：映射原生 fatigue type：輕擊 `blocked_attack`、單手重擊 `blocked_sv_sweep`、雙手重擊 `blocked_sv_cleave`。
- `Damage.hook(mod, settings)`：安裝以下 Hook：
  - `ActionSweep._do_overlap`：暫時把同隊玩家加入 enemy lookup，讓原生命中／格擋路徑處理 PVP。
  - `ActionSweep._play_character_impact`：PVP 玩家格擋時先呼叫原生 `DamageUtils.check_block()`，使用正確 fatigue type，再把回傳的格擋結果交回原生 impact。
  - `DamageUtils.calculate_damage`：套用 PVP 倍率，並在實際命中時計算武器碰撞。

武器碰撞規則：

- Light vs Light：雙方卡刀；若武器體積沒有命中玩家，不造成傷害；若掃描實際命中玩家，仍造成傷害。
- Heavy vs Heavy：雙方卡刀；若武器體積沒有命中玩家，不造成傷害；若掃描實際命中玩家，仍造成傷害。
- Light vs Heavy：Light 卡刀，Heavy 繼續；雙方只有在武器掃描實際命中玩家時才造成傷害。

`DamageUtils.calculate_damage()` 只會在原生武器掃描已命中玩家後執行，因此不能用「雙方目前都在攻擊」直接把傷害歸零。攻擊分類與 weapon class 仍會被解析，但不會覆蓋原生命中結果。

### `pvp_stagger.lua`

- `enabled(mod)`：踉蹌 Hook 的開關檢查。
- `install_templates()`：註冊 PVP 踉蹌模板名稱；網路狀態實際使用已存在的 `slow_bomb` lookup，避免自訂 NetworkLookup ID 不一致。
- `Stagger.apply(unit, template, duration, attacker)`：伺服器端套用 overpowered 狀態並記錄結束時間；已有踉蹌時不刷新時間。
- `Stagger.update(mod)`：逾時解除踉蹌；PVP 停用時立即清除所有 Mod 造成的踉蹌。
- `Stagger.clear(unit)`：解除單一玩家的踉蹌並同步至用戶端。
- `Stagger.hook(mod)`：安裝以下 Hook：
  - `DamageUtils.server_apply_hit`：踉蹌期間受到有效、未格擋傷害時立即解除踉蹌。
  - `GenericStatusExtension.blocked_attack`：原生完美格擋成立時，讓攻擊者踉蹌 3 秒。
  - `ActionPushStagger.client_owner_post_update`：讓推擊可作用於玩家，命中後讓受擊者踉蹌 1 秒。

## 維護規則

1. 所有新的 PVP 行為先加在 `pvp_damage.lua` 或 `pvp_stagger.lua`，不要修改原始遊戲 source code。
2. 每個 Hook 開頭都必須保留 `pvp_enabled` 檢查；停用時必須直接呼叫 `func(...)`。
3. 傷害與格擋應優先呼叫原生 `DamageUtils`／`GenericStatusExtension`，不要複製原生 fatigue 或角度計算。
4. 武器分類只能使用 `get_weapon_template().buff_type`；不要建立武器名稱白名單。
5. 修改 action 或 damage profile 判定時，確認同時支援本地預測、伺服器命中與遠端玩家。
6. 修改後重新 build，確認 `resource_packages/fff PvP/fff PvP.package` 仍包含兩個 Lua 路徑：

   ```text
   scripts/mods/fff PvP/*
   scripts/mods/pvp_mod/*
   ```

## 測試清單

- 關閉 `PVP Enabled`：玩家互打不應造成 PVP 傷害、格擋或踉蹌。
- 開啟 PVP：聊天應收到完整規則廣播。
- 驗證 25% 與其他傷害倍率即時生效。
- 驗證內圈、外圈與角度外格擋。
- 驗證 1H／2H 重擊 fatigue 分別為 4／16。
- 驗證完美格擋、推擊與受傷解除踉蹌。
- 驗證 Light/Light、Heavy/Heavy、Light/Heavy、Heavy/Light 碰撞結果。
- 驗證蓄力階段被命中時仍遵守原生可打斷規則。

目前環境若沒有 `luac`，無法執行 bytecode 語法檢查；最終仍需在實際 VT2 + VMF 環境進行載入、網路同步與多人測試。
