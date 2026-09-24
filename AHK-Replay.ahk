#Requires AutoHotkey v2.0
#SingleInstance Force
CoordMode "Mouse", "Screen"
CoordMode "ToolTip", "Screen"

; ================= 配置 =================
INTER_LOOP_MS := 3000       ; 每轮回放之间的固定间隔(毫秒)
MAX_WAIT_COMPRESS := 2500   ; 录制时超过此长度的停顿压缩到该值(毫秒)，保留页面过渡时间
RECORD_DIR := A_ScriptDir "\recordings"
; ========================================

; ================= 快捷键 =================
; F2  开始/结束录制（结束自动保存并询问回放次数）
; F4  回放最近一次录制
; F5  从 recordings 文件夹挑选一个录制回放
; F12 急停/退出（回放中按了立即停止）
; 录制内容：鼠标点击、滚轮、Ctrl+V（含当时的剪贴板内容）、Ctrl+A、Esc、Enter
; ==========================================

global events := [], recording := false, startTick := 0, lastName := ""
global replaying := false, savedClip := ""

try DirCreate RECORD_DIR

; ---------- 日志 ----------
LogEvent(msg) {
    try FileAppend A_Hour ":" A_Min ":" A_Sec " " msg "`n", A_ScriptDir "\ahk-replay.log", "UTF-8"
}

; ---------- 剪贴板内容转义（行式文件存储：仅转义 反斜杠 与 换行） ----------
ClipEscape(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`r", "\r")
    return s
}

; 单遍扫描解码（避免 \\n 被二次误解析为换行）
ClipUnescape(s) {
    out := ""
    i := 1
    n := StrLen(s)
    while (i <= n) {
        c := SubStr(s, i, 1)
        if (c = "\") {
            nxt := SubStr(s, i + 1, 1)
            switch nxt {
                case "n": out .= "`n", i += 2
                case "r": out .= "`r", i += 2
                case "\": out .= "\", i += 2
                default:  out .= c, i += 1
            }
        } else {
            out .= c
            i += 1
        }
    }
    return out
}

; ---------- 录制 ----------
ToggleRecord() {
    global events, recording, startTick, lastName, replaying
    if (replaying) {
        ToolTip "回放进行中，无法录制（按 F12 急停后再试）"
        SetTimer () => ToolTip(), -2000
        return
    }
    if !recording {
        events := []
        recording := true
        startTick := A_TickCount
        ToolTip "● 录制中… 完成操作后按 F2（点击/滚轮/Ctrl+V/Ctrl+A/Esc/Enter 都会记录）"
        LogEvent("REC_ON")
    } else {
        recording := false
        if (events.Length = 0) {
            ToolTip "本次没有录到任何动作"
            SetTimer () => ToolTip(), -1500
            LogEvent("REC_OFF 空")
            return
        }
        name := ""
        loop {
            ib := InputBox("给这段录制起个名字：", "保存录制", "w300 h130",
                "rec-" . FormatTime(, "MMdd-HHmmss"))
            if (ib.Result = "OK") {
                name := Trim(ib.Value)
                break
            }
            if (MsgBox("取消将丢弃这段录制（" events.Length " 个动作），确定？", "确认丢弃", "YesNo Icon!") = "Yes") {
                LogEvent("REC_OFF cancel_discarded len=" events.Length)
                return
            }
        }
        if (name = "")
            name := "rec-" . FormatTime(, "MMdd-HHmmss")
        name := SanitizeName(name)
        if SaveRecording(name) {
            lastName := name
            ToolTip "已保存：recordings\" name ".ahkr（" events.Length " 个动作）"
            SetTimer () => ToolTip(), -1800
            LogEvent("REC_OFF name=" name " len=" events.Length)
        } else {
            ToolTip "保存失败，未写入文件（本次动作仍可回放）"
            SetTimer () => ToolTip(), -3000
            LogEvent("REC_OFF save_failed len=" events.Length)
        }
        AskCountAndReplay(events)
    }
}

OnClick() {
    global events, recording, startTick
    if recording {
        MouseGetPos &x, &y
        events.Push({t: A_TickCount - startTick, k: "click", x: x, y: y, clip: ""})
    }
}

OnWheel(kind) {
    global events, recording, startTick
    if recording {
        MouseGetPos &x, &y
        events.Push({t: A_TickCount - startTick, k: kind, x: x, y: y, clip: ""})
    }
}

; 键盘自动重复过滤：同一热键 400ms 内连续触发视为按住不放
IsKeyRepeat() {
    return (A_ThisHotkey = A_PriorHotkey && A_TimeSincePriorHotkey < 400)
}

OnKey(kind) {
    global events, recording, startTick
    if (recording && !IsKeyRepeat())
        events.Push({t: A_TickCount - startTick, k: kind, x: 0, y: 0, clip: ""})
}

; 粘贴事件：把当时的剪贴板内容一起记录（回放时还原）
OnPaste() {
    global events, recording, startTick
    if (recording && !IsKeyRepeat())
        events.Push({t: A_TickCount - startTick, k: "v", x: 0, y: 0, clip: A_Clipboard})
}

; ---------- 存取 ----------
; 清洗录制名：非法文件名字符替换为 _、保留设备名加前缀、长度截断
SanitizeName(name) {
    name := RegExReplace(name, '[\\/:*?"<>|]', "_")
    if (StrLen(name) > 80)
        name := SubStr(name, 1, 80)
    name := RTrim(name, ". ")
    if (RegExMatch(name, "i)^(con|prn|aux|nul|com[1-9]|lpt[1-9])($|\.)"))
        name := "_" name
    if (RTrim(name, "_. ") = "")
        name := "rec-" . FormatTime(, "MMdd-HHmmss")
    return name
}

SaveRecording(name) {
    global events, RECORD_DIR
    s := ""
    for ev in events
        s .= ev.t "|" ev.k "|" ev.x "|" ev.y "|" ClipEscape(ev.clip) "`n"
    file := RECORD_DIR "\" name ".ahkr"
    try {
        if FileExist(file) {
            if (MsgBox("已存在同名录制「" name "」，覆盖旧文件？", "确认覆盖", "YesNo Icon!") != "Yes") {
                LogEvent("SAVE_SKIP_OVERWRITE name=" name)
                return false
            }
            FileDelete file
        }
        FileAppend s, file, "UTF-8"
    } catch Error as e {
        ToolTip "保存失败：" e.Message "（本次录制未写入文件）"
        SetTimer () => ToolTip(), -3000
        LogEvent("SAVE_FAIL name=" name " msg=" e.Message)
        return false
    }
    LogEvent("SAVED " name " len=" events.Length)
    return true
}

LoadRecordingFile(file) {
    evs := [], bad := 0
    try txt := FileRead(file, "UTF-8")
    catch Error as e {
        ToolTip "读取录制文件失败：" e.Message
        SetTimer () => ToolTip(), -3000
        LogEvent("LOAD_FAIL file=" file " msg=" e.Message)
        return evs
    }
    first := true
    for line in StrSplit(txt, "`n", "`r") {
        if (first) {                 ; BOM 只会出现在首行
            line := StrReplace(line, Chr(0xFEFF), "")
            first := false
        }
        if (line = "")
            continue
        p := StrSplit(line, "|", , 5)
        if (p.Length < 4 || !IsInteger(Trim(p[1])) || !IsInteger(Trim(p[3])) || !IsInteger(Trim(p[4]))) {
            bad++
            continue
        }
        ; clip 直接取原始第 5 字段（不做整行 Trim，保证粘贴内容与录制时完全一致）
        clip := (p.Length >= 5) ? ClipUnescape(p[5]) : ""
        evs.Push({t: Integer(Trim(p[1])), k: Trim(p[2]), x: Integer(Trim(p[3])), y: Integer(Trim(p[4])), clip: clip})
    }
    if (bad > 0) {
        ToolTip "已忽略 " bad " 行无效记录（文件损坏或被手改）"
        SetTimer () => ToolTip(), -3000
        LogEvent("LOAD_BAD count=" bad " file=" file)
    }
    return evs
}

LatestRecording() {
    global RECORD_DIR
    best := "", bestTime := 0
    Loop Files RECORD_DIR "\*.ahkr" {
        t := A_LoopFileTimeModified
        if (t > bestTime) {
            bestTime := t
            best := A_LoopFileFullPath
        }
    }
    return best
}

; ---------- 回放 ----------
AskCountAndReplay(evs) {
    global replaying
    replaying := true
    try {
        ib := InputBox("回放多少次？（回放中按 F12 急停）", "循环回放", "w300 h140", "1")
        if (ib.Result != "OK")
            return
        if !(ib.Value ~= '^\d+$') {
            MsgBox "请输入数字"
            return
        }
        n := (StrLen(ib.Value) > 15) ? 100000 : Integer(ib.Value)
        if (n < 1) {
            MsgBox "回放次数至少为 1"
            return
        }
        if (n > 100000) {
            n := 100000
            ToolTip "回放次数已限制为 100000"
            SetTimer () => ToolTip(), -2000
        }
        Replay(n, evs)
    } catch Error as e {
        ToolTip "回放异常中止：" e.Message
        SetTimer () => ToolTip(), -3000
        LogEvent("REPLAY_FAIL msg=" e.Message)
    } finally {
        replaying := false
        RestoreClipboard()
    }
}

Replay(n, evs) {
    global INTER_LOOP_MS, MAX_WAIT_COMPRESS, savedClip
    if (evs.Length = 0) {
        ToolTip "没有可回放的动作"
        SetTimer () => ToolTip(), -1500
        return
    }
    if !CoordsInRange(evs) {
        ToolTip "警告：录制中部分坐标超出当前屏幕范围，回放可能点击错误位置（目标窗口被移动？）"
        Sleep 2500
    }
    ToolTip "3 秒后开始回放… 请切到目标窗口"
    Sleep 3000
    savedClip := A_Clipboard
    LogEvent("REPLAY n=" n " evs=" evs.Length)

    Loop n {
        prev := 0
        for ev in evs {
            wait := ev.t - prev
            prev := ev.t
            if (wait > MAX_WAIT_COMPRESS)
                wait := MAX_WAIT_COMPRESS
            if (wait > 0)
                Sleep wait
            switch ev.k {
                case "click":  Click ev.x, ev.y
                case "v":
                    if (ev.clip = "") {
                        LogEvent("SKIP_EMPTY_CLIP t=" ev.t)
                    } else {
                        A_Clipboard := ev.clip
                        if !ClipWait(0.5, 1) {
                            A_Clipboard := ev.clip
                            ClipWait(0.5, 1)
                        }
                        Send "^v"
                    }
                case "a":      Send "^a"
                case "esc":    Send "{Esc}"
                case "enter":  Send "{Enter}"
                case "wu":     MouseMove ev.x, ev.y, 2
                               Send "{WheelUp}"
                case "wd":     MouseMove ev.x, ev.y, 2
                               Send "{WheelDown}"
            }
        }
        ToolTip "回放完成 " A_Index "/" n "  (F12 停止)"
        if (A_Index < n)
            Sleep INTER_LOOP_MS
    }
    ToolTip "全部回放完成 ✓"
    SetTimer () => ToolTip(), -2000
    LogEvent("REPLAY_DONE n=" n)
}

; 检查点击/滚轮坐标是否都在当前虚拟屏幕范围内
CoordsInRange(evs) {
    vx := SysGet(76)
    vy := SysGet(77)
    vw := SysGet(78)
    vh := SysGet(79)
    for ev in evs {
        if (ev.k = "click" || ev.k = "wu" || ev.k = "wd")
            if (ev.x < vx || ev.y < vy || ev.x >= vx + vw || ev.y >= vy + vh)
                return false
    }
    return true
}

; 还原回放前的用户剪贴板（还原一次后清空，避免覆盖回放结束后新复制的内容）
RestoreClipboard(_reason := "", _code := 0) {
    global savedClip
    if (savedClip != "") {
        try A_Clipboard := savedClip
        savedClip := ""
    }
}

ReplayLast() {
    global lastName, RECORD_DIR, recording, replaying
    if (recording) {
        ToolTip "录制进行中，先按 F2 结束录制"
        SetTimer () => ToolTip(), -2000
        return
    }
    if (replaying) {
        ToolTip "回放进行中，按 F12 急停后再试"
        SetTimer () => ToolTip(), -2000
        return
    }
    file := lastName = "" ? LatestRecording() : RECORD_DIR "\" lastName ".ahkr"
    if (file = "" || !FileExist(file)) {
        file := LatestRecording()
    }
    if (file = "" || !FileExist(file)) {
        ToolTip "还没有录制文件，先按 F2 录一次"
        SetTimer () => ToolTip(), -2000
        return
    }
    evs := LoadRecordingFile(file)
    AskCountAndReplay(evs)
}

PickAndReplay() {
    global RECORD_DIR, recording, replaying
    if (recording) {
        ToolTip "录制进行中，先按 F2 结束录制"
        SetTimer () => ToolTip(), -2000
        return
    }
    if (replaying) {
        ToolTip "回放进行中，按 F12 急停后再试"
        SetTimer () => ToolTip(), -2000
        return
    }
    file := FileSelect(1, RECORD_DIR, "选择录制文件", "录制文件 (*.ahkr)")
    if (file = "")
        return
    evs := LoadRecordingFile(file)
    AskCountAndReplay(evs)
}

; ---------- 快捷键 ----------
F2:: ToggleRecord()
F4:: ReplayLast()
F5:: PickAndReplay()
F12:: ExitApp
~LButton:: OnClick()
~^v:: OnPaste()
~^a:: OnKey("a")
~Esc:: OnKey("esc")
~Enter:: OnKey("enter")
~WheelUp:: OnWheel("wu")
~WheelDown:: OnWheel("wd")

; ---------- 启动提示 ----------
OnExit RestoreClipboard
ToolTip "已就绪：F2 录制 | F4 回放最近 | F5 选择录制文件 | F12 退出"
LogEvent("LAUNCH")
SetTimer () => ToolTip(), -3500
