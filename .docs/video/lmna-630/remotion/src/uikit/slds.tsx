import React, { useLayoutEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { continueRender, delayRender, staticFile } from "remotion";

// Salesforce UI rebuilt 1:1 from the official Lightning Design System (2026-09-24,
// James: "exactly look like 1-1 from Salesforce, those curves"). SLDS 2.264.1 from npm
// (code BSD-3; icons/images CC BY-ND 4.0, used unmodified, credited on the end card).
//
// SLDS has no scoped build, so it renders inside a SHADOW ROOT: its global styles can't
// leak into the other films. `:root` tokens are rewritten to `:host`, relative image urls
// made absolute. CSS animations don't render in Remotion, so anything that moves (spinner,
// typing, highlights) is driven by frame in the components below.
//
// Every block has a FIXED height so positions are exact maths (SCREEN constants), never
// estimated off a screenshot (review rule, 2026-09-24).

let CSS_P: Promise<string> | null = null;
const loadCss = () =>
  (CSS_P ??= fetch(staticFile("slds/styles/salesforce-lightning-design-system.min.css")).then((r) => r.text())
    .then((t) => t.replace(/:root/g, ":host").replace(/url\(\.\.\//g, `url(${staticFile("slds/")}`)));
const HOST_CSS = `:host{display:block;font-family:var(--slds-g-font-family-base,-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif);font-size:13px;line-height:1.5;color:#181818;-webkit-font-smoothing:antialiased}
*,*::before,*::after{box-sizing:border-box;animation:none!important;transition:none!important}`;

export const SldsRoot: React.FC<{ style?: React.CSSProperties; children: React.ReactNode }> = ({ style, children }) => {
  const ref = useRef<HTMLDivElement>(null);
  const [root, setRoot] = useState<ShadowRoot | null>(null);
  const [h] = useState(() => delayRender("slds css"));
  useLayoutEffect(() => {
    const el = ref.current!;
    const sr = el.shadowRoot ?? el.attachShadow({ mode: "open" });
    loadCss().then((css) => {
      if (!sr.querySelector("style[data-slds]")) { const s = document.createElement("style"); s.setAttribute("data-slds", ""); s.textContent = css + HOST_CSS; sr.appendChild(s); }
      setRoot(sr); continueRender(h);
    }).catch(() => continueRender(h));
  }, [h]);
  return <div ref={ref} style={style}>{root ? createPortal(<>{children}</>, root) : null}</div>;
};

const SPRITE = (set: "utility" | "standard") => staticFile(`slds/icons/${set}-sprite/svg/symbols.svg`);
export const Icon: React.FC<{ name: string; set?: "utility" | "standard"; className?: string; style?: React.CSSProperties }> = ({ name, set = "utility", className = "slds-icon slds-icon_x-small slds-icon-text-default", style }) => (
  <svg className={className} style={style} aria-hidden="true"><use href={`${SPRITE(set)}#${name}`} /></svg>
);

// ---- virtual screen geometry (px, 1440 x 900) -------------------------------------
export const SCREEN = { w: 1440, h: 900, header: 50, nav: 40, rec: { y: 102, h: 118 }, path: { y: 232, h: 56 }, card: { y: 300 }, tabs: 44, sectionTitle: 36, fields: { y: 404, rowH: 52, x: 26, colW: 698, w: 684 } };
export const fieldRect = (col: number, row: number): [number, number, number, number] => [SCREEN.fields.x + col * SCREEN.fields.colW, SCREEN.fields.y + row * SCREEN.fields.rowH, SCREEN.fields.w, SCREEN.fields.rowH];

export const GlobalHeader: React.FC = () => (
  <header className="slds-global-header_container" style={{ position: "relative", height: SCREEN.header }}>
    <div className="slds-global-header slds-grid slds-grid_align-spread" style={{ height: SCREEN.header }}>
      <div className="slds-global-header__item"><div className="slds-global-header__logo" /></div>
      <div className="slds-global-header__item slds-global-header__item_search" style={{ flex: "0 1 460px" }}>
        <div className="slds-form-element"><div className="slds-form-element__control slds-input-has-icon slds-input-has-icon_left">
          <Icon name="search" className="slds-icon slds-input__icon slds-input__icon_left slds-icon-text-default" />
          <input className="slds-input" placeholder="Search..." readOnly style={{ width: 460 }} />
        </div></div>
      </div>
      <div className="slds-global-header__item">
        <ul className="slds-global-actions">
          {["favorite", "add", "question", "setup", "notification"].map((n) => (
            <li key={n} className="slds-global-actions__item"><button className="slds-button slds-button_icon slds-button_icon-container slds-global-actions__item-action"><Icon name={n} className="slds-button__icon slds-global-header__icon" /></button></li>
          ))}
          <li className="slds-global-actions__item"><span className="slds-avatar slds-avatar_circle slds-avatar_small" style={{ background: "#0176d3", color: "#fff", display: "inline-flex", alignItems: "center", justifyContent: "center", fontSize: 11, fontWeight: 700 }}>AN</span></li>
        </ul>
      </div>
    </div>
  </header>
);

export const ContextBar: React.FC<{ app?: string; items?: string[]; active?: string }> = ({ app = "IDR App", items = ["Home", "Leads", "Accounts", "Contacts", "Cases", "CPT Codes", "Payments", "Reports", "Dashboards"], active = "Cases" }) => (
  <div className="slds-context-bar" style={{ height: SCREEN.nav }}>
    <div className="slds-context-bar__primary">
      <div className="slds-context-bar__item slds-context-bar__dropdown-trigger slds-dropdown-trigger slds-no-hover">
        <div className="slds-context-bar__icon-action"><button className="slds-button slds-icon-waffle_container slds-context-bar__button"><span className="slds-icon-waffle">{["r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8", "r9"].map((r) => <span key={r} className={`slds-${r}`} />)}</span></button></div>
        <span className="slds-context-bar__label-action slds-context-bar__app-name"><span className="slds-truncate">{app}</span></span>
      </div>
    </div>
    <nav className="slds-context-bar__secondary"><ul className="slds-grid">
      {items.map((it) => <li key={it} className={`slds-context-bar__item${it === active ? " slds-is-active" : ""}`}><a className="slds-context-bar__label-action"><span className="slds-truncate">{it}</span></a></li>)}
    </ul></nav>
  </div>
);

export const RecordHeader: React.FC<{ object: string; title: string; icon?: string; details: [string, string | null][]; actions?: string[] }> = ({ object, title, icon = "case", details, actions = ["Edit", "Delete", "Clone", "Upload File"] }) => (
  <div className="slds-page-header slds-page-header_record-home" style={{ height: SCREEN.rec.h }}>
    <div className="slds-page-header__row">
      <div className="slds-page-header__col-title"><div className="slds-media">
        <div className="slds-media__figure"><span className={`slds-icon_container slds-icon-standard-${icon}`}><Icon set="standard" name={icon} className="slds-icon slds-page-header__icon" /></span></div>
        <div className="slds-media__body"><div className="slds-page-header__name"><div className="slds-page-header__name-title"><h1><span>{object}</span><span className="slds-page-header__title slds-truncate">{title}</span></h1></div></div></div>
      </div></div>
      <div className="slds-page-header__col-actions"><div className="slds-page-header__controls"><div className="slds-page-header__control">
        <ul className="slds-button-group-list">{actions.map((a) => <li key={a}><button className="slds-button slds-button_neutral">{a}</button></li>)}</ul>
      </div></div></div>
    </div>
    <div className="slds-page-header__row slds-page-header__row_gutters"><div className="slds-page-header__col-details">
      <ul className="slds-page-header__detail-row">{details.map(([k, v]) => <li key={k} className="slds-page-header__detail-block"><div className="slds-text-title slds-truncate">{k}</div>{v === null ? <div style={{ height: 10, width: 64, borderRadius: 5, background: "#e5e5e5", marginTop: 6 }} /> : <div className="slds-truncate">{v}</div>}</li>)}</ul>
    </div></div>
  </div>
);

/** SLDS path. `current` index; stages before it are complete. */
export const Path: React.FC<{ stages: string[]; current: number }> = ({ stages, current }) => (
  <div className="slds-path" style={{ height: SCREEN.path.h, padding: "10px 12px" }}>
    <div className="slds-grid slds-path__track"><div className="slds-grid slds-path__scroller-container"><div className="slds-path__scroller"><div className="slds-path__scroller_inner">
      <ul className="slds-path__nav" role="listbox">
        {stages.map((s, i) => (
          <li key={s} className={`slds-path__item ${i < current ? "slds-is-complete" : i === current ? "slds-is-current slds-is-active" : "slds-is-incomplete"}`} role="presentation">
            <a className="slds-path__link" role="option"><span className="slds-path__stage"><Icon name="check" className="slds-icon slds-icon_x-small" /></span><span className="slds-path__title">{s}</span></a>
          </li>
        ))}
      </ul>
    </div></div></div></div>
  </div>
);

export const Tabs: React.FC<{ items: string[]; active: string }> = ({ items, active }) => (
  <div className="slds-tabs_default" style={{ height: SCREEN.tabs }}><ul className="slds-tabs_default__nav" role="tablist">
    {items.map((i) => <li key={i} className={`slds-tabs_default__item${i === active ? " slds-is-active" : ""}`} role="presentation"><a className="slds-tabs_default__link" role="tab">{i}</a></li>)}
  </ul></div>
);

/** Read-only record field. `value` may be partial (typing); `flash` 0..1 is Salesforce's yellow "just updated" wash. */
export const Field: React.FC<{ label: string; value: React.ReactNode; flash?: number; editing?: boolean }> = ({ label, value, flash = 0, editing }) => (
  <div className="slds-form-element slds-form-element_readonly slds-form-element_horizontal" style={{ height: SCREEN.fields.rowH, margin: 0, display: "flex", alignItems: "center", background: flash > 0 ? `rgba(255,232,122,${0.75 * flash})` : undefined, borderRadius: 4, position: "relative" }}>
    <span className="slds-form-element__label" style={{ width: "36%", maxWidth: "36%" }}>{label}</span>
    <div className="slds-form-element__control" style={{ flex: 1, paddingLeft: 0, marginLeft: 0 }}>
      {editing ? <input className="slds-input" readOnly value={typeof value === "string" ? value : ""} style={{ height: 32 }} /> : <div className="slds-form-element__static" style={{ whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis", maxWidth: 400 }}>{value}</div>}
    </div>
    <button className="slds-button slds-button_icon" style={{ position: "absolute", right: 6 }}><Icon name="edit" className="slds-button__icon slds-button__icon_hint" /></button>
  </div>
);

export const Section: React.FC<{ title: string; children: React.ReactNode }> = ({ title, children }) => (
  <div className="slds-section slds-is-open" style={{ margin: 0 }}>
    <h3 className="slds-section__title" style={{ height: SCREEN.sectionTitle, margin: 0 }}>
      <button className="slds-button slds-section__title-action"><Icon name="switch" className="slds-section__title-action-icon slds-button__icon slds-button__icon_left" /><span className="slds-truncate">{title}</span></button>
    </h3>
    <div className="slds-section__content" style={{ paddingTop: 8 }}>{children}</div>
  </div>
);

export const Toast: React.FC<{ tone: "success" | "info"; title: string; body?: string }> = ({ tone, title, body }) => (
  <div className="slds-notify_container slds-is-relative" style={{ position: "relative", width: "auto" }}>
    <div className={`slds-notify slds-notify_toast slds-theme_${tone}`} role="status" style={{ margin: 0, minWidth: 480 }}>
      <span className={`slds-icon_container slds-icon-utility-${tone === "success" ? "success" : "email"} slds-m-right_small slds-no-flex slds-align-top`}><Icon name={tone === "success" ? "success" : "email"} className="slds-icon slds-icon_small" /></span>
      <div className="slds-notify__content"><h2 className="slds-text-heading_small">{title}</h2>{body ? <p>{body}</p> : null}</div>
    </div>
  </div>
);

/** SLDS brand spinner, rotated by frame (CSS keyframes don't render). */
export const Spinner: React.FC<{ frame: number }> = ({ frame }) => (
  <div style={{ position: "relative", width: 28, height: 28, rotate: `${(frame * 14) % 360}deg` }}>
    <div className="slds-spinner slds-spinner_x-small slds-spinner_brand" role="status" style={{ position: "absolute", left: "50%", top: "50%" }}><div className="slds-spinner__dot-a" /><div className="slds-spinner__dot-b" /></div>
  </div>
);
