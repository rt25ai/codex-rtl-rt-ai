# ChatGPT Desktop RTL Patch for Hebrew (Codex & OWL)

A drop-in RTL patch for the **unified ChatGPT desktop app** ("Powered by
Codex & OWL" - the app that merged ChatGPT Work and Codex) that improves
Hebrew and Arabic writing, mixed RTL/LTR text, punctuation alignment, and
keeps code blocks left-to-right.

תיקון RTL לאפליקציית **ChatGPT Desktop החדשה** (המאוחדת - Work + Codex)
שמשפר כתיבה בעברית ובערבית, טקסט מעורב עברית/אנגלית, יישור סימני פיסוק
ושמירה על בלוקי קוד משמאל לימין.

> גרסאות קודמות של הפרויקט פיצ'ו את **Codex Desktop**. האפליקציה החדשה היא
> אותה חבילת חנות (`OpenAI.Codex`) עם מיתוג ChatGPT - הפאצ' תומך בשתיהן,
> ומשדרג אוטומטית התקנות ישנות של `Codex-RT-AI`.

By **RT-AI** - [rt-ai.co.il](https://rt-ai.co.il)

![Platform Windows](https://img.shields.io/badge/Windows-supported-blue) ![macOS experimental](https://img.shields.io/badge/macOS-experimental-lightgrey) ![Admin](https://img.shields.io/badge/admin-not_required-brightgreen) ![License MIT](https://img.shields.io/badge/license-MIT-green)

---
## Who is this for?

This project is for Hebrew and Arabic users of the unified ChatGPT desktop
app (the Codex & OWL one) who want natural RTL writing inside the app,
without changing their original installation.
מיועד למשתמשי עברית וערבית שעובדים עם אפליקציית ChatGPT Desktop החדשה
ורוצים כתיבה טבעית מימין לשמאל בתוך האפליקציה, בלי לשנות את ההתקנה המקורית.

## התקנה - שורה אחת

### Windows

פתחו **PowerShell** (לא חייב admin), הדביקו את השורה הזו, ולחצו Enter:

```powershell
irm https://raw.githubusercontent.com/rt25ai/codex-rtl-rt-ai/v0.3.0/install-online.ps1 | iex
```

זהו. בסוף יופיע קיצור דרך בשם **"ChatGPT"** על שולחן העבודה ובתפריט Start,
והוא יפתח את הגרסה המפוצ'ת עם תמיכה ב-RTL. אם הייתה לכם התקנה ישנה של
**Codex-RT-AI** - היא תוסר ותוחלף אוטומטית.

> **דרישות:** [Node.js (LTS)](https://nodejs.org/) + אפליקציית ChatGPT
> (חבילת `OpenAI.Codex`) מ-Microsoft Store.
> לא נדרשים admin / takeown / שינויי הרשאות.

> **אם Windows מציג אזהרת אבטחה (`Trojan:Win32/ClickFix`):**
> זו **התרעת שווא (false positive)** - לא וירוס. Windows Defender מסמן כך כל
> פקודה מסוג `irm ... | iex` בגלל **צורת ההתקנה**, לא בגלל התוכן (הסיומת `!MTB`
> פירושה ניחוש היוריסטי, לא חתימה של נוזקה ידועה). הסקריפט פתוח לקריאה כאן
> ב-GitHub - הוא רק יוצר **עותק מקומי** של האפליקציה עם תמיכת עברית, בלי לגעת
> בהתקנה המקורית, ב-registry או ב-services. אם האזהרה קופצת: **Windows Security
> → היסטוריית הגנה → בחרו בפריט → "אפשר"**, ואז הריצו שוב את הפקודה.

### macOS - experimental

macOS support is included but has not yet been personally tested by the
author on the unified app. The script follows the standard pattern for
patching Electron apps on macOS (ad-hoc `codesign`, best-effort ASAR fuse)
and reuses the same payload as the Windows version. Confirmations, issue
reports and pull requests are very welcome.

פתחו **Terminal** והדביקו:

```bash
curl -fsSL https://raw.githubusercontent.com/rt25ai/codex-rtl-rt-ai/v0.3.0/install-online.sh | bash
```

זה ייצור `~/Applications/ChatGPT-RT-AI.app` עם תמיכת RTL, מבלי לגעת
ב-`ChatGPT.app` המקורי תחת `/Applications` (או `Codex.app` בהתקנות ישנות -
שניהם מזוהים אוטומטית).

> **דרישות:** [Node.js](https://nodejs.org/) (`brew install node`) +
> Xcode CLI tools (`xcode-select --install`) + ChatGPT Desktop מותקן
> ב-`/Applications` (מ-https://chatgpt.com/download).
> שימו לב: **"ChatGPT Classic"** היא האפליקציה הישנה (Swift) - הפאצ' לא
> מיועד לה ולא ייגע בה.
> אם נתקלתם בבעיה - פתחו [issue](https://github.com/rt25ai/codex-rtl-rt-ai/issues) או PR.

## Before / After

![Before and after RTL behavior in the ChatGPT desktop app](docs/rtl-before-after.png)

**מה משתנה בפועל:**

- לפני הפאצ': טקסט עברי יכול להיצמד לצד הלא נכון, סימני שאלה ופיסוק נראים
  הפוכים, ושורות מעורבות עברית/אנגלית מרגישות שבורות.
- אחרי הפאצ': הודעות בעברית מיושרות לימין, הפיסוק נשאר במקום הטבעי, ובלוקי
  קוד ממשיכים להופיע משמאל לימין כדי שלא יישברו.

**מה הפאצ' מזהה אוטומטית:**

- ✅ עברית/ערבית בתוך ה-composer → ה-input מיישר לימין בזמן הקלדה.
- ✅ עברית/ערבית בתשובות streaming מהמודל → כל פסקה מיושרת בנפרד לפי השפה.
- ✅ טקסט מעורב (עברית + אנגלית באותה שורה) → first-strong detection.
- ✅ בלוקי קוד (` ``` `, `<pre>`, Monaco, CodeMirror) → **תמיד LTR**.
- ✅ Inline code (`` `כך` ``) → LTR גם בתוך פסקה ב-RTL.
- ✅ סימני פיסוק "שמטיילים" - מיוצבים עם `unicode-bidi: plaintext`.

## הסרה / סטטוס

**Windows:**
```powershell
irm https://raw.githubusercontent.com/rt25ai/codex-rtl-rt-ai/v0.3.0/uninstall-online.ps1 | iex
```

**macOS:**
```bash
curl -fsSL https://raw.githubusercontent.com/rt25ai/codex-rtl-rt-ai/v0.3.0/uninstall-online.sh | bash
```

המקור (תחת `WindowsApps` ב-Windows, או `/Applications` ב-Mac)
**לא מושפע** וממשיך לעבוד רגיל. ההסרה מנקה גם שאריות של התקנות
`Codex-RT-AI` ישנות.

## עדכוני האפליקציה

כשהאפליקציה מתעדכנת (Microsoft Store ב-Windows / Sparkle ב-Mac), מותקנת
**משימת עדכון אוטומטית** שמפעילה את הפאצ' מחדש על הגרסה החדשה - בחלון
מוסתר, בלי לגעת בסשן פתוח. אין צורך להריץ שוב את המתקין; אם בכל זאת משהו
נתקע, הרצה חוזרת של שורת ההתקנה תמיד מיישרת את המצב.

## תוקן: חלון CMD שקופץ (למי שהתקין גרסה קודמת)

אם התקנת **גרסה קודמת** והבחנת בחלון שחור (CMD/PowerShell) שקופץ כל כמה דקות -
זה היה באג במשימת העדכון האוטומטי: היא הופעלה אחרי **כל** עדכון Microsoft Store
ובחלון גלוי, במקום רק אחרי עדכון של האפליקציה. **תוקן.**

לא צריך להסיר ולהתקין מחדש - התקנת v0.3.0 (השורה הרגילה למעלה) מחליפה את
המשימה הישנה במשימה החדשה והנקייה. לחלופין, לתיקון המשימה בלבד:

```powershell
irm https://raw.githubusercontent.com/rt25ai/codex-rtl-rt-ai/main/fix-autoupdate-online.ps1 | iex
```

---

## איך זה עובד מבפנים

1. מוצא את האפליקציה תחת `C:\Program Files\WindowsApps\OpenAI.Codex_...\app`
   (זו חבילת ה-MSIX של ChatGPT המאוחדת - היא שמרה על מזהה Codex).
2. מעתיק אותה ל-`%LOCALAPPDATA%\Programs\ChatGPT-RT-AI`.
3. מחלץ את `resources\app.asar` עם `@electron/asar`.
4. מוסיף את `codex-rtl-payload.js` כ-prefix ל-bundles של ה-webview:
   - `webview\assets\index-*.js`, `app-main-*.js`, `composer-*.js`
5. אורז מחדש את `app.asar`.
6. מנסה לכבות את `EnableEmbeddedAsarIntegrityValidation` (best-effort:
   בבניית ה-OWL החדשה אין fuse sentinel בכלל - וזה בסדר, היא לא אוכפת
   asar integrity).
7. כותב marker (`resources\rt-ai-chatgpt-rtl-patch.json`).
8. יוצר קיצורי דרך `ChatGPT.lnk` ב-Desktop וב-Start Menu (ומסיר קיצורי
   `Codex.lnk` ישנים).
9. רושם משימת עדכון אוטומטי שמפעילה re-patch אחרי עדכון Store.

הכל ב-`%LOCALAPPDATA%` - תיקייה user-writable. אין שינוי ב-`WindowsApps`,
ב-registry, או ב-services.

## מבנה הפרויקט

```text
.
|-- codex-rtl-payload.js     # ה-JS שמוזרק ל-webview (משותף Win/Mac)
|--
|-- patch.ps1                # סקריפט ראשי - Windows
|-- install.bat              # מתקין בדאבל-קליק - Windows
|-- install-online.ps1       # מתקין one-liner - Windows
|-- uninstall.bat            # מסיר בדאבל-קליק - Windows
|-- uninstall-online.ps1     # מסיר one-liner - Windows
|-- status.bat               # סטטוס - Windows
|-- fix-autoupdate-online.ps1 # hotfix למשימת עדכון של גרסאות ישנות
|--
|-- patch.sh                 # סקריפט ראשי - macOS
|-- install-online.sh        # מתקין one-liner - macOS
|-- uninstall-online.sh      # מסיר one-liner - macOS
|--
|-- tests/verify-static.ps1  # בדיקות סטטיות
|-- README.md
|-- LICENSE
```

## ולידציה

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\verify-static.ps1
```

## Known limitations

- **macOS support is experimental** - the script follows a standard
  Electron-patching pattern, but the author has not personally tested it
  on the unified app.
- **The patched copy is not officially signed.** It carries an ad-hoc
  signature on macOS, and on Windows it is no longer MSIX-signed.
- **Future UI changes** may move bundle filenames. The script will
  bail out with a clear error rather than patch the wrong file - report
  it as an issue and a new release will be cut.
- **Trust model:** the one-line installer is pinned to a signed release
  tag (currently `v0.3.0`), not the `main` branch. A compromised `main`
  cannot silently affect users who run the published one-liner. The repo
  is small and auditable - read the scripts before you run them.

---

## ⚠️ Disclaimer - הסרת אחריות

**אנא קראו לפני ההתקנה.**

- **שימוש אישי בלבד.** הכלי הזה מסופק כ-AS-IS, בלי שום אחריות מפורשת או
  משתמעת, וניתן לשימוש על אחריותו הבלעדית של המשתמש.
- **לא קשור ל-OpenAI.** הפאצ' אינו מוצר רשמי של OpenAI ואינו מאושר על-ידם.
  ChatGPT® ,Codex® ו-OpenAI® הם סימנים מסחריים של בעליהם.
- **מתקן העתק, לא את המקור.** הסקריפט יוצר העתק של האפליקציה תחת תיקיית
  המשתמש ומפעיל אותו. ההתקנה המקורית מ-Microsoft Store נשארת ללא שינוי.
  עם זאת, ההעתק כבר אינו חתום ב-MSIX integrity, מה שאומר ש-Windows לא
  מתייחס אליו כאל אפליקציה חתומה.
- **ASAR integrity fuse.** בבנייה הנוכחית (OWL) אין fuse בכלל; אם עתידית
  יהיה - הפאצ' מכבה אותו בהעתק כדי שיוכל לטעון את ה-asar המעודכן. השלכה:
  אם רוצים לחזור לחתימה מקורית - מסירים את ההעתק (`uninstall.bat`)
  ומשתמשים שוב במקור.
- **עדכונים מטופלים ע"י משימת ה-auto-update.** עדכון Store מעדכן את המקור;
  המשימה המתוזמנת מזהה זאת ומפצ'ת מחדש את ההעתק (כשהוא לא רץ). אפשר תמיד
  להריץ שוב את ההתקנה ידנית.
- **שימוש משפיע על your user data.** ההעתק חולק תיקיית user data עם המקור
  (אותו `UserDataDirectoryName`). זה אומר שכניסה, היסטוריית שיחות ופרטי
  משתמש אמורים להישמר.
- **ללא ערבות לתפקוד עתידי.** OpenAI יכולים בכל עת לשנות את מבנה ה-bundles
  הפנימי של האפליקציה. אם זה קורה - הפאצ' יעצור עם שגיאה ברורה (במקום
  לפגוע בקובץ הלא נכון בשקט), והוא ידרוש עדכון.
- **רישיון:** MIT. ראו [LICENSE](LICENSE). אין שום warranty (כולל לעניין
  merchantability ו-fitness for a particular purpose), והמחברים אינם
  אחראים לכל נזק ישיר, עקיף, מקרי, או תוצאתי שייגרם משימוש בכלי.

הוגן? לפני שמשתמשים, ודאו שאתם מבינים מה הסקריפט עושה. הקוד פתוח -
[קראו אותו](patch.ps1).

---

### English summary

Drop-in RTL (right-to-left) patch for the **unified ChatGPT desktop app**
("Powered by Codex & OWL" - MSIX package `OpenAI.Codex` on Windows,
`/Applications/ChatGPT.app` on macOS). Windows support is stable; macOS
support is experimental. Detects Hebrew/Arabic text in the composer and
streamed responses, aligns RTL content naturally, keeps code blocks LTR.
Existing Codex-RT-AI installs from older versions of this patcher are
migrated automatically.

**Install (one-liner, no admin):**

```powershell
# Windows (PowerShell)
irm https://raw.githubusercontent.com/rt25ai/codex-rtl-rt-ai/v0.3.0/install-online.ps1 | iex
```

```bash
# macOS (Terminal) - untested on the unified app, contributions welcome
curl -fsSL https://raw.githubusercontent.com/rt25ai/codex-rtl-rt-ai/v0.3.0/install-online.sh | bash
```

**Notes:**

- No admin / sudo required.
- The original app (under `WindowsApps` on Windows / `/Applications` on
  macOS) is left untouched. Only a copy under the user profile is patched.
- Shortcuts/launchers named "ChatGPT" point to the patched copy.
- An auto-update task re-applies the patch after the app updates.
- "ChatGPT Classic" (the old native app) is NOT a target of this patch.
- Personal use, AS-IS, MIT license. Not affiliated with OpenAI.

**Installed an earlier version and see a CMD window pop up every few minutes?**
That was an auto-update task bug (it fired on every Microsoft Store update, in a
visible window). Fixed - installing v0.3.0 replaces the old task. To fix just
the task (one UAC prompt):

```powershell
irm https://raw.githubusercontent.com/rt25ai/codex-rtl-rt-ai/main/fix-autoupdate-online.ps1 | iex
```

## Known limitations

- macOS support is experimental.
- The patched copy is not an officially signed OpenAI app.
- Future UI changes may require an update to this patch.
