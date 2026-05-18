# Codex RTL Patch for Windows — by RT-AI

> תמיכה אוטומטית בעברית/ערבית (RTL) ל-OpenAI Codex Desktop על Windows.
> Adds automatic Hebrew/Arabic (RTL) support to OpenAI Codex Desktop on Windows.

מזהה טקסט עברי/ערבי בזמן אמת ב-composer וב-streaming של התשובות, מיישר אותו
לימין באופן טבעי, ושומר על בלוקי קוד ב-LTR. **לא דורש הרשאות admin** ולא נוגע
בהתקנה המקורית של Codex.

By **RT-AI** — [rt-ai.co.il](https://rt-ai.co.il)

![status](https://img.shields.io/badge/platform-windows-blue) ![status](https://img.shields.io/badge/admin-not%20required-green) ![status](https://img.shields.io/badge/license-MIT-lightgrey)

---

## התקנה (3 אפשרויות)

### 1. הכי קל — דאבל-קליק

הורידו את הריפו (ZIP / `git clone`), ואז דאבל-קליק על **`install.bat`**.

### 2. שורת פקודה אחת ב-PowerShell

פתחו PowerShell (מכל תיקייה — לא חייב להיות בתיקיית הפרויקט) והדביקו:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\COdex-RTL-rt-ai\patch.ps1" -Install
```

החליפו `C:\path\to\COdex-RTL-rt-ai` בנתיב שבו שמרתם את הפרויקט.

### 3. מתקין מקוון (one-liner)

```powershell
irm https://raw.githubusercontent.com/<your-user>/codex-rtl-rt-ai/main/install-online.ps1 | iex
```

> דרישה יחידה: **[Node.js](https://nodejs.org/) (LTS)** מותקן.
> ה-MS Store version של Codex Desktop צריך להיות מותקן.

## איך זה נראה אחרי התקנה

- מופיע **קיצור דרך "Codex"** על שולחן העבודה ובתפריט Start.
- לחיצה עליו פותחת Codex עם תמיכה מלאה ב-RTL (העברית מיושרת לימין, אנגלית
  ב-LTR, קוד נשאר LTR).
- ההתקנה המקורית של Codex (תחת `WindowsApps`) נשארת ללא שינוי.

## הסרה

דאבל-קליק על **`uninstall.bat`** (או `patch.ps1 -Uninstall`).
מוחק את ההעתק המתוקן ואת השורטקאטים. המקור לא מושפע.

## בדיקת סטטוס

דאבל-קליק על **`status.bat`** — מציג מקור Codex, נתיב הפאצ', מצב fuse של Electron.

---

## מה הפאצ' עושה

- מזהה עברית/ערבית בזמן אמת ב-composer ובתשובות streaming.
- מיישר אוטומטית `.ProseMirror` (תיבת הקלט) לימין כשמקלידים RTL.
- מיישר הודעות בזמן streaming מהמודל.
- שומר `pre`, `code`, Monaco/CodeMirror, שורות עם syntax highlighting — LTR.
- מתקין העתק מתוקן ב-`%LOCALAPPDATA%\Programs\Codex-RT-AI`.
- **לא** נוגע ב-Codex המקורי תחת `WindowsApps` (היא מוגנת על-ידי MSIX).

## דרישות

- **Windows** עם Codex Desktop מותקן (גרסת MSIX מ-Microsoft Store).
- **[Node.js](https://nodejs.org/)** — נדרש בשביל `npx.cmd` (`@electron/asar`,
  `@electron/fuses`).
- אין צורך ב-admin.

## איך זה עובד מבפנים

1. מוצא את Codex תחת `C:\Program Files\WindowsApps\OpenAI.Codex_...\app`.
2. מעתיק אותו ל-`%LOCALAPPDATA%\Programs\Codex-RT-AI`.
3. מחלץ את `resources\app.asar` בעזרת `@electron/asar`.
4. מוסיף את `codex-rtl-payload.js` כ-prefix ל-bundles של ה-webview:
   - `webview\assets\index-*.js`
   - `webview\assets\app-main-*.js`
   - `webview\assets\composer-*.js`
5. אורז מחדש את `app.asar`.
6. מכבה את ה-fuse של ASAR integrity (`EnableEmbeddedAsarIntegrityValidation=off`)
   על ה-`Codex.exe` המועתק — נדרש כי שינינו את ה-archive.
7. כותב marker (`resources\rt-ai-codex-rtl-patch.json`).
8. יוצר קיצורי דרך `Codex.lnk` ב-Desktop וב-Start Menu.

## עדכוני Codex

כש-Codex Desktop מתעדכן (דרך Microsoft Store), המקור תחת `WindowsApps` יוחלף
אבל **הפאצ' שלך לא יושפע** — ההעתק שלך תחת LocalAppData ימשיך לעבוד עם הגרסה
הקודמת. כדי לקבל את הגרסה החדשה עם RTL, פשוט הריצו שוב את `install.bat` והוא
יעתיק ויפאצ' את הגרסה החדשה.

## למה העתק ולא in-place?

`WindowsApps` היא תיקייה מוגנת ע"י MSIX/TrustedInstaller:
- שינויים בה דורשים admin + `takeown`/`icacls`.
- שינויים שוברים את חתימת ה-MSIX.
- עדכונים אוטומטיים מהחנות ידרסו את הפאצ'.

לכן הפאצ' עובד על העתק נפרד תחת פרופיל המשתמש — בטוח, ללא admin, וניתן לחזרה.

## הערות

- ההעתק עשוי לשתף user data עם Codex המקורי (שם האפליקציה ב-Electron זהה).
- אם Codex משנה את מבנה ה-bundles הפנימי, הסקריפט יעצור עם שגיאה ברורה במקום
  לתקן בשקט את הקובץ הלא נכון.

## ולידציה

הרצת בדיקות סטטיות מקומיות:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\verify-static.ps1
```

## מבנה הפרויקט

```text
.
|-- install.bat              # מתקין בדאבל-קליק
|-- uninstall.bat            # מסיר בדאבל-קליק
|-- status.bat               # בדיקת סטטוס בדאבל-קליק
|-- patch.ps1                # הסקריפט הראשי
|-- codex-rtl-payload.js     # ה-JS שמוזרק ל-webview
|-- tests/verify-static.ps1  # בדיקות סטטיות
|-- README.md
|-- LICENSE
```

## רישיון

MIT — ראו [LICENSE](LICENSE).

נבנה על ידי **RT-AI** לטובת קהילת המשתמשים בעברית.
Issues / PRs welcome.

---

### English summary

Drop-in RTL (right-to-left) patch for OpenAI Codex Desktop on Windows.
Detects Hebrew/Arabic text in the composer and streamed responses, aligns RTL
content naturally, keeps code blocks LTR.

- No admin required.
- Original Codex (under WindowsApps) is left untouched.
- A patched copy lives at `%LOCALAPPDATA%\Programs\Codex-RT-AI`.
- Desktop and Start Menu shortcuts named "Codex" point to the patched copy.

Install: double-click `install.bat` (requires [Node.js](https://nodejs.org/)).
Uninstall: double-click `uninstall.bat`.
