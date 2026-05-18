# Codex RTL Patch for Windows - by RT-AI

> תמיכה אוטומטית בעברית/ערבית (RTL) ל-OpenAI Codex Desktop על Windows.
> Adds automatic Hebrew (RTL) support to OpenAI Codex Desktop on Windows.

מזהה טקסט עברי/ערבי בזמן אמת ב-composer וב-streaming של התשובות, מיישר אותו
לימין באופן טבעי, ושומר על בלוקי קוד ב-LTR. **לא דורש הרשאות admin** ולא נוגע
בהתקנה המקורית של Codex.

By **RT-AI** - [rt-ai.co.il](https://rt-ai.co.il)

![platform](https://img.shields.io/badge/platform-windows-blue) ![admin](https://img.shields.io/badge/admin-not%20required-green) ![license](https://img.shields.io/badge/license-MIT-lightgrey)

---

## התקנה - שורה אחת ב-PowerShell

פתחו **PowerShell** (לא חייב admin), הדביקו את השורה הזו, ולחצו Enter:

```powershell
irm https://raw.githubusercontent.com/rt25ai/codex-rtl-rt-ai/main/install-online.ps1 | iex
```

זהו. בסוף יופיע שורטקאט בשם **"Codex"** על שולחן העבודה ובתפריט Start, ותפעיל
את הגרסה החדשה עם תמיכה ב-RTL.

> **דרישה יחידה:** [Node.js (LTS)](https://nodejs.org/) מותקן ו-Codex Desktop
> מותקן מ-Microsoft Store. *לא נדרשים admin / takeown / שינויי הרשאות.*

## Before / After

<table dir="ltr">
<tr><th>בלי הפאצ' (Before)</th><th>עם הפאצ' (After)</th></tr>
<tr>
<td>

```
+----------------------------------+
| Codex                            |
+----------------------------------+
| Response from Codex:             |
|                                  |
| ?Python -ב for loop כתוב לי   |
| .for i in range(10):             |
|     print(i)                     |
|                                  |
| [Composer]                       |
| | אנגלית and קוד עם שאלה כתוב   |
+----------------------------------+
       ^ העברית "נשפכת" שמאלה,
         הסימני שאלה והפיסוק בצד הלא נכון,
         הצמדה לימין לא קיימת.
```

</td>
<td>

```
+----------------------------------+
| Codex                            |
+----------------------------------+
|             :Codex מ Response    |
|                                  |
|   ?כתוב לי for loop ב-Python    |
|             for i in range(10):  |
|                     print(i)     |
|                                  |
|                       [Composer] |
| כתוב שאלה עם קוד and אנגלית |   |
+----------------------------------+
       ^ העברית מיושרת לימין,
         פיסוק במקום הנכון,
         בלוקי קוד נשארים LTR.
```

</td>
</tr>
</table>

**מה הפאצ' מזהה אוטומטית:**

- ✅ עברית/ערבית בתוך ה-composer → ה-input מיישר לימין בזמן הקלדה.
- ✅ עברית/ערבית בתשובות streaming מהמודל → כל פסקה מיושרת בנפרד לפי השפה.
- ✅ טקסט מעורב (עברית + אנגלית באותה שורה) → first-strong detection.
- ✅ בלוקי קוד (` ``` `, `<pre>`, Monaco, CodeMirror) → **תמיד LTR**.
- ✅ Inline code (`` `כך` ``) → LTR גם בתוך פסקה ב-RTL.
- ✅ סימני פיסוק "שמטיילים" — מיוצבים עם `unicode-bidi: plaintext`.

## הסרה / סטטוס

אחרי שמתקינים, בתיקייה שנפתחה זמנית — או דרך הריפו המקומי:

```powershell
# הסרה
irm https://raw.githubusercontent.com/rt25ai/codex-rtl-rt-ai/main/uninstall-online.ps1 | iex

# או דאבל-קליק על uninstall.bat בתיקייה המקומית
```

המקור של Codex (תחת `WindowsApps`) **לא מושפע** וממשיך לעבוד רגיל.

## עדכוני Codex

כש-Codex Desktop מתעדכן ב-Microsoft Store, ההעתק המתוקן שלך **לא מתעדכן
אוטומטית**. כדי לקבל את הגרסה החדשה עם RTL, פשוט הריצו שוב את אותה שורה
מההתקנה — הסקריפט יזהה את הגרסה החדשה, יעתיק אותה, ויפאצ'.

---

## איך זה עובד מבפנים

1. מוצא את Codex תחת `C:\Program Files\WindowsApps\OpenAI.Codex_...\app`.
2. מעתיק אותו ל-`%LOCALAPPDATA%\Programs\Codex-RT-AI`.
3. מחלץ את `resources\app.asar` עם `@electron/asar`.
4. מוסיף את `codex-rtl-payload.js` כ-prefix ל-bundles של ה-webview:
   - `webview\assets\index-*.js`, `app-main-*.js`, `composer-*.js`
5. אורז מחדש את `app.asar`.
6. מכבה את `EnableEmbeddedAsarIntegrityValidation` ב-`Codex.exe` (נדרש אחרי
   שינוי ב-asar) באמצעות `@electron/fuses`.
7. כותב marker (`resources\rt-ai-codex-rtl-patch.json`).
8. יוצר קיצורי דרך `Codex.lnk` ב-Desktop וב-Start Menu.

הכל ב-`%LOCALAPPDATA%` — תיקייה user-writable. אין שינוי ב-`WindowsApps`,
ב-registry, או ב-services.

## מבנה הפרויקט

```text
.
|-- install.bat              # מתקין בדאבל-קליק (מקומי)
|-- install-online.ps1       # מתקין one-liner מ-GitHub
|-- uninstall.bat            # מסיר בדאבל-קליק
|-- status.bat               # בדיקת סטטוס
|-- patch.ps1                # הסקריפט הראשי
|-- codex-rtl-payload.js     # ה-JS שמוזרק ל-webview
|-- tests/verify-static.ps1  # בדיקות סטטיות
|-- README.md
|-- LICENSE
```

## ולידציה

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\verify-static.ps1
```

---

## ⚠️ Disclaimer - הסרת אחריות

**אנא קראו לפני ההתקנה.**

- **שימוש אישי בלבד.** הכלי הזה מסופק כ-AS-IS, בלי שום אחריות מפורשת או
  משתמעת, וניתן לשימוש על אחריותו הבלעדית של המשתמש.
- **לא קשור ל-OpenAI.** הפאצ' אינו מוצר רשמי של OpenAI ואינו מאושר על-ידם.
  Codex® ו-OpenAI® הם סימנים מסחריים של בעליהם.
- **מתקן העתק, לא את המקור.** הסקריפט יוצר העתק של Codex תחת תיקיית המשתמש
  ומפעיל אותו. ההתקנה המקורית מ-Microsoft Store נשארת ללא שינוי. עם זאת,
  ההעתק כבר אינו חתום ב-MSIX integrity, מה שאומר ש-Windows לא מתייחס אליו
  כאל אפליקציה חתומה.
- **מבטל ASAR integrity fuse.** הפאצ' מכבה fuse של Electron בהעתק כדי שיוכל
  לטעון את ה-asar המעודכן. השלכה: אם רוצים לחזור לחתימה מקורית — מסירים את
  ההעתק (`uninstall.bat`) ומשתמשים שוב במקור.
- **MSIX מעדכן את המקור, לא את ההעתק.** עדכון של Codex דרך Microsoft Store
  לא יעדכן את ההעתק המתוקן. צריך להריץ שוב את ההתקנה כדי לאמץ את הגרסה
  החדשה.
- **שימוש משפיע על your user data של Codex.** ההעתק חולק תיקיית user data
  עם המקור (שם האפליקציה ב-Electron זהה). זה אומר שכניסה, היסטוריית שיחות
  ופרטי משתמש אמורים להישמר.
- **ללא ערבות לתפקוד עתידי.** OpenAI יכולים בכל עת לשנות את מבנה ה-bundles
  הפנימי של Codex Desktop. אם זה קורה — הפאצ' יעצור עם שגיאה ברורה (במקום
  לפגוע בקובץ הלא נכון בשקט), והוא ידרוש עדכון.
- **רישיון:** MIT. ראו [LICENSE](LICENSE). אין שום warranty (כולל לעניין
  merchantability ו-fitness for a particular purpose), והמחברים אינם
  אחראים לכל נזק ישיר, עקיף, מקרי, או תוצאתי שייגרם משימוש בכלי.

הוגן? לפני שמשתמשים, ודאו שאתם מבינים מה הסקריפט עושה. הקוד פתוח —
[קראו אותו](patch.ps1).

---

### English summary

Drop-in RTL (right-to-left) patch for OpenAI Codex Desktop on Windows.
Detects Hebrew/Arabic text in the composer and streamed responses, aligns RTL
content naturally, keeps code blocks LTR.

**Install (one-liner, no admin):**

```powershell
irm https://raw.githubusercontent.com/rt25ai/codex-rtl-rt-ai/main/install-online.ps1 | iex
```

**Notes:**

- No admin required.
- Original Codex (under WindowsApps) is left untouched — only a copy at
  `%LOCALAPPDATA%\Programs\Codex-RT-AI` is patched.
- Desktop and Start Menu shortcuts named "Codex" point to the patched copy.
- Personal use, AS-IS, MIT license. Not affiliated with OpenAI.
