// ===========================================================================
// RT-AI Codex RTL Patch - Smart RTL Detection & Alignment
//
// Adds automatic right-to-left support to OpenAI Codex Desktop on Windows.
// Detects Hebrew and Arabic text in the composer and streamed responses,
// aligns RTL content naturally, and keeps code blocks left-to-right.
//
// Part of the RT-AI tooling suite (https://rt-ai.co.il).
// ===========================================================================

// --- RT-AI CODEX RTL PATCH START ---
;(function () {
    "use strict";

    if (typeof window === "undefined" || typeof document === "undefined") return;
    if (window.__RT_AI_CODEX_RTL_PATCH__) return;
    window.__RT_AI_CODEX_RTL_PATCH__ = true;

    var INPUT_SEL = ".ProseMirror, [contenteditable=\"true\"], textarea, input[type=\"text\"], input:not([type])";
    var CODE_SEL = "pre, code, .cm-editor, .monaco-editor, .shiki, .hljs, [data-language]";
    var TEXT_SEL = "p, li, h1, h2, h3, h4, h5, h6, blockquote, td, th, summary, label, legend, dt, dd, figcaption, caption";
    var INLINE_SEL = "div, span, button, a, label";

    function isRTLChar(ch) {
        var code = ch.charCodeAt(0);
        return (code >= 0x0590 && code <= 0x05ff) ||
            (code >= 0x0600 && code <= 0x06ff) ||
            (code >= 0x0750 && code <= 0x077f) ||
            (code >= 0x08a0 && code <= 0x08ff) ||
            (code >= 0xfb1d && code <= 0xfdff) ||
            (code >= 0xfe70 && code <= 0xfeff);
    }

    function hasRTL(text) {
        if (!text) return false;
        for (var i = 0; i < text.length; i++) {
            if (isRTLChar(text[i])) return true;
        }
        return false;
    }

    function firstStrong(text) {
        if (!text) return null;
        for (var i = 0; i < text.length; i++) {
            if (isRTLChar(text[i])) return "rtl";
            if (/[A-Za-z]/.test(text[i])) return "ltr";
        }
        return null;
    }

    function textWithoutCode(el) {
        var out = "";
        var nodes = el.childNodes || [];
        for (var i = 0; i < nodes.length; i++) {
            var node = nodes[i];
            if (node.nodeType === 3) {
                out += node.textContent || "";
            } else if (node.nodeType === 1 && !node.matches(CODE_SEL)) {
                out += textWithoutCode(node);
            }
        }
        return out;
    }

    function stripLeadingLTR(text) {
        return String(text || "")
            .replace(/^[\s]*(?:[\w.-]+\.[A-Za-z]{1,8})\s*/g, "")
            .replace(/https?:\/\/\S+/g, "")
            .replace(/[\w.-]+[\/\\][\w.\/\\-]+/g, "")
            .replace(/`[^`]+`/g, "")
            .replace(/^[\s\d()[\]{}.,:;'"!?@#$%^&*_+=|<>/-]+/g, "");
    }

    function detectTextDir(text) {
        if (!text || !String(text).trim()) return null;
        var dir = firstStrong(text);
        if (dir === "rtl") return "rtl";
        if (!hasRTL(text)) return "ltr";
        dir = firstStrong(stripLeadingLTR(text));
        return dir === "rtl" ? "rtl" : "ltr";
    }

    function detectElDir(el) {
        var full = el.textContent || "";
        if (!hasRTL(full)) return null;
        var noCode = textWithoutCode(el);
        return detectTextDir(noCode) === "rtl" ? "rtl" : null;
    }

    function qsa(root, selector) {
        var base = root && root.querySelectorAll ? root : document;
        var els = Array.prototype.slice.call(base.querySelectorAll(selector));
        if (root && root.matches && root.matches(selector)) els.unshift(root);
        return els;
    }

    function isInsideCode(el) {
        return !!(el && el.closest && el.closest(CODE_SEL));
    }

    function isInsideInput(el) {
        return !!(el && el.closest && el.closest(INPUT_SEL));
    }

    function forceCodeLTR(root) {
        qsa(root, CODE_SEL).forEach(function (el) {
            el.dir = "ltr";
            el.style.direction = "ltr";
            el.style.textAlign = "left";
            el.style.unicodeBidi = el.tagName === "CODE" ? "isolate" : "embed";
        });
    }

    function applyBlockDir(el, dir) {
        if (dir === "rtl") {
            el.dir = "rtl";
            el.style.direction = "rtl";
            el.style.textAlign = "start";
            el.style.unicodeBidi = "plaintext";
            if (el.tagName === "LI") {
                el.style.listStylePosition = "inside";
                var list = el.closest("ul, ol");
                if (list && !list.hasAttribute("dir")) {
                    list.dir = "rtl";
                    list.style.direction = "rtl";
                    list.style.textAlign = "start";
                }
            }
        } else if (el.hasAttribute("dir")) {
            el.removeAttribute("dir");
            el.style.direction = "";
            el.style.textAlign = "";
            el.style.unicodeBidi = "";
            if (el.tagName === "LI") el.style.listStylePosition = "";
        }
    }

    function processText(root) {
        qsa(root, TEXT_SEL).forEach(function (el) {
            if (isInsideInput(el) || isInsideCode(el)) return;
            applyBlockDir(el, detectElDir(el));
        });

        qsa(root, "ul, ol").forEach(function (el) {
            if (isInsideInput(el) || isInsideCode(el)) return;
            applyBlockDir(el, detectElDir(el));
        });
    }

    function processInlineContainers(root) {
        qsa(root, INLINE_SEL).forEach(function (el) {
            if (isInsideInput(el) || isInsideCode(el)) return;
            if (el.querySelector && el.querySelector(TEXT_SEL + ", ul, ol, pre, code, table")) return;
            var text = (el.textContent || "").trim();
            if (text.length < 2) return;

            if (hasRTL(text)) {
                el.dir = detectTextDir(text) || "rtl";
                el.style.textAlign = "start";
                el.style.unicodeBidi = "plaintext";
            } else if (el.hasAttribute("dir")) {
                el.removeAttribute("dir");
                el.style.textAlign = "";
                el.style.unicodeBidi = "";
            }
        });
    }

    function readInputText(el) {
        if ("value" in el) return el.value || "";
        return el.textContent || el.innerText || "";
    }

    function processInputElement(el) {
        var dir = detectTextDir(readInputText(el));
        if (dir === "rtl") {
            el.dir = "rtl";
            el.style.direction = "rtl";
            el.style.textAlign = "right";
            el.style.unicodeBidi = "plaintext";
        } else if (dir === "ltr") {
            el.dir = "ltr";
            el.style.direction = "ltr";
            el.style.textAlign = "left";
            el.style.unicodeBidi = "plaintext";
        } else {
            el.removeAttribute("dir");
            el.style.direction = "";
            el.style.textAlign = "";
            el.style.unicodeBidi = "";
        }
    }

    function processInputs(root) {
        qsa(root, INPUT_SEL).forEach(processInputElement);
    }

    function processAll(root) {
        var base = root || document.body || document;
        processText(base);
        processInlineContainers(base);
        processInputs(base);
        forceCodeLTR(base);
    }

    function injectStyles() {
        if (document.getElementById("rt-ai-codex-rtl-styles")) return;
        var style = document.createElement("style");
        style.id = "rt-ai-codex-rtl-styles";
        style.textContent = [
            ".ProseMirror[dir=\"rtl\"],textarea[dir=\"rtl\"],input[dir=\"rtl\"]{direction:rtl!important;text-align:right!important;unicode-bidi:plaintext!important}",
            ".ProseMirror[dir=\"ltr\"],textarea[dir=\"ltr\"],input[dir=\"ltr\"]{direction:ltr!important;text-align:left!important;unicode-bidi:plaintext!important}",
            "[dir=\"rtl\"]{direction:rtl!important;text-align:start!important}",
            "[dir=\"ltr\"]{direction:ltr!important}",
            "p,li,h1,h2,h3,h4,h5,h6,blockquote,td,th,summary,label,legend,dt,dd,figcaption,caption{unicode-bidi:plaintext}",
            "pre,.cm-editor,.monaco-editor,.shiki,.hljs,[data-language]{direction:ltr!important;text-align:left!important;unicode-bidi:embed!important}",
            "code{direction:ltr!important;unicode-bidi:isolate!important}"
        ].join("\n");
        document.head.appendChild(style);
    }

    function schedule(root) {
        if (window.__RT_AI_CODEX_RTL_TIMER__) return;
        window.__RT_AI_CODEX_RTL_TIMER__ = window.setTimeout(function () {
            window.__RT_AI_CODEX_RTL_TIMER__ = null;
            processAll(root || document.body || document);
        }, 50);
    }

    function init() {
        injectStyles();
        processAll(document.body || document);

        document.addEventListener("input", function (event) {
            var target = event.target;
            if (!target || !target.matches) return;
            if (target.matches(INPUT_SEL) || (target.closest && target.closest(INPUT_SEL))) {
                processInputElement(target.closest(INPUT_SEL) || target);
                schedule(document.body || document);
            }
        }, true);

        var observer = new MutationObserver(function (mutations) {
            var roots = [];
            for (var i = 0; i < mutations.length; i++) {
                var mutation = mutations[i];
                if (mutation.type === "characterData" && mutation.target.parentElement) {
                    roots.push(mutation.target.parentElement);
                }
                for (var j = 0; j < mutation.addedNodes.length; j++) {
                    var node = mutation.addedNodes[j];
                    if (node.nodeType === 1) roots.push(node);
                }
            }

            if (roots.length === 0) return;
            if (roots.length <= 30) {
                roots.forEach(processAll);
                processInputs(document);
            } else {
                schedule(document.body || document);
            }
        });

        observer.observe(document.body, { childList: true, subtree: true, characterData: true });
        console.info("[RT-AI Codex RTL] patch active");
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", init, { once: true });
    } else {
        init();
    }
})()
// --- RT-AI CODEX RTL PATCH END ---
