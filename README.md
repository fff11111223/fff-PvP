# fff PvP

《Warhammer: Vermintide 2》的休閒 Hero↔Hero PvP Mod，目標是在大廳或等待玩家時提供近戰對戰；關閉 PvP 後，所有 Hook 都放行原生函式，不改變一般 PvE。

## 目前戰鬥規則

- PvP 對象限定為 Hero Player ↔ Hero Player。
- 玩家傷害倍率由 `PVP Damage (%)` 控制，預設 25%。
- 普通 Block、Timed Block、Parry、Fatigue、Block Broken 與 Push 優先使用 VT2 原生流程。
- Light 命中另一名玩家時視為 PvP clash：攻擊者使用原生 block-impact / hit-stop，該次 Light damage 被取消。
- Heavy vs Heavy 使用武器姿態 OBB approximation 判斷碰撞；碰撞時雙方卡刀。
- Light vs Heavy 時 Light 卡刀，Heavy 繼續。
- Full-charge Heavy 使用每把武器原生 `allowed_chain_actions.start_time` 作為 Heavy release boundary，可穿透 PvP Player Block/Parry，不增加傷害倍率或自訂 Stagger。
- PvP Hero 命中反應使用原生 `hit_react_type`：Light → `light`，Heavy/Full Heavy → `heavy`。
- 不使用自訂 PvP Stagger；`pvp_stagger.lua` 已移除。

## Build 與檔案結構

Build 入口：

```text
fff PvP.mod
resource_packages/fff PvP/fff PvP.package
scripts/mods/fff PvP/fff PvP.lua
```

主要模組位於 `scripts/mods/pvp_mod/`：

| 檔案 | 用途 |
|---|---|
| `pvp_damage.lua` | PvP 命中、傷害倍率、Block、fatigue、Hit Reaction、Full Heavy 與攻擊中止 |
| `pvp_weapon_clash.lua` | 武器分類、攻擊類型與 OBB clash approximation |
| `pvp_weapon_tracker.lua` | Server 追蹤 remote 3P weapon unit 的位置與旋轉 |
| `pvp_settings.lua` | PvP 開關與傷害倍率 |
| `pvp_bot_drill.lua` | 選用的 Bot 測試工具 |

`pvp_stagger.lua` 不再存在，也不可重新加入舊的 `set_pushed(true)`、`stagger_until` 或自訂 duration 系統。

## 原生流程與 Hook

### 傷害與受擊反應

```text
ActionSweep
→ rpc_attack_hit
→ DamageUtils.server_apply_hit
→ DamageUtils.add_damage_network_player
→ PlayerUnitHealthExtension.add_damage
→ recently_damaged()
→ CharacterStateHelper
→ 原生 Player hit reaction
```

PvP 只在 `PlayerUnitHealthExtension.add_damage()` 對兩名 Hero Player 指定：

```text
light_attack  → hit_react_type = "light"
heavy_attack  → hit_react_type = "heavy"
```

不使用 `light_push`、`medium_push`、`heavy_push`，也不建立新的動畫資源。

### Block / Parry

`ActionSweep._play_character_impact()` 對 PvP Hero 命中呼叫原生：

```text
DamageUtils.check_block()
→ GenericStatusExtension.blocked_attack()
→ fatigue / timed block / parry / block broken
```

Perfect Block 保留原生 Timed Block 判定。成功後，攻擊者的 `ActionSweep` 會進入原生 block impact / `hit_shield_stop_anim`，並以 `abort_attack = true` 中止攻擊。

### Full-charge Heavy

`WeaponUnitExtension.start_action()` 讀取目前武器的 `allowed_chain_actions`，以該武器自己的 Heavy release `start_time` 判斷是否達到 Full Heavy；不使用固定秒數。

Full Heavy 的 PvP 行為只是在 Block 判定前跳過 `DamageUtils.check_block()`，其餘 Damage、Hit Reaction、網路 RPC 仍走原生流程。

## 武器 Clash 限制

VT2 官方 source 沒有 Hero weapon-vs-weapon 的原生 ActionSweep collision。Mod 使用 Server-side visual weapon pose OBB approximation：

- visual weapon unit：只提供位置與旋轉。
- damage unit：仍由原生 ActionSweep 負責真正命中玩家。
- physics actor：Mod 不建立新的 physics actor。

因此 OBB 不是原生 swept weapon collision；它只在原生 Player→Player hit 已發生後作為額外 clash 判定。Remote husk 若沒有可用的 current action state，Heavy clash 可能回傳 unavailable，並維持原生傷害。

## PVP OFF 保證

每個 PvP Hook 都先檢查 `pvp_enabled`。停用時：

- 不計算 OBB。
- 不更新 clash 或 Full Heavy 狀態。
- 不改 damage、Block、Parry、Push 或 Hit Reaction。
- PvE Enemy ↔ Hero 完全維持原生。

## 維護規則

1. 不修改官方 source；只在 `scripts/mods/pvp_mod/` 使用 Hook。
2. 新 PvP 規則必須限制在 Hero Player↔Hero Player。
3. 優先呼叫 `DamageUtils`、`GenericStatusExtension`、`PlayerUnitHealthExtension` 等原生 API。
4. 武器分類使用 `inventory_extension:get_slot_data("slot_melee")` 與 `get_item_template(slot_data).buff_type`，不可建立武器名稱白名單。
5. 不新增 Push hook、custom damage RPC、physics actor、Stagger counter 或自訂動畫。
6. 修改後執行 `git diff --check`，再於 VT2 + VMF 多人環境驗證。

## 測試清單

- PvP OFF：玩家互打、PvE、Push、Block、Parry 與 Hit Reaction 均為原生。
- PvP ON：Light 命中玩家會卡刀，且顯示原生 Light impact。
- PvP ON：Heavy 命中玩家顯示原生 Heavy hit reaction。
- Full Heavy 可穿透 Player Block/Parry。
- Timed Block 會中止攻擊者的原生 ActionSweep。
- 1H/2H Heavy Block fatigue 分別使用 `blocked_sv_sweep` / `blocked_sv_cleave`。
- Heavy OBB clash、Light/Heavy 優先級與 remote husk state availability。
- Server/client hit reaction 與多人同步。

目前若環境沒有 `luac` 或 `luacheck`，只能執行 `git diff --check` 與靜態檢查；最終仍需進遊戲驗證動畫、武器姿態與網路同步。
