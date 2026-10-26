---
name: Aurora website
description: Editorial sibling to nmapaye.com with a calm native product illustration.
colors:
  ink: "#101010"
  paper: "#f7f5ee"
  white: "#ffffff"
  yellow: "#ffeb09"
  muted: "#55514a"
typography:
  display:
    fontFamily: "Barlow Condensed, Arial Narrow, sans-serif"
    fontSize: "clamp(4rem, 7.5vw, 6rem)"
    fontWeight: 800
    lineHeight: 0.94
    letterSpacing: "-0.025em"
  body:
    fontFamily: "Space Grotesk, Arial, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.6
rounded:
  controls: "0px"
spacing:
  small: "12px"
  medium: "24px"
  large: "48px"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.white}"
    rounded: "{rounded.controls}"
    padding: "12px 20px"
---

# Design System: Aurora website

## Overview

**Creative North Star: An honest product, in the developer's editorial family.**
The marketing frame uses firm typography, large yellow and ink fields, and
visible rules. The synthetic native illustration retains Aurora's warm surfaces
and wave. The website is a sibling to the portfolio, with its own product story.
This specification applies only within website/. Native design.md is unchanged.

## Colors

Yellow leads the hero and interactive preview. Ink supplies rules, text and the
release section. Paper carries reading sections; white gives the evidence card
and footer contrast. Muted text is reserved for secondary supporting content.

**The Evidence Rule.** Color never replaces the text distinguishing a synthetic
value, an estimate, or a missing record.

## Typography

Self-hosted Barlow Condensed Extra Bold supplies uppercase headings, with a
maximum hero size of 96px. Space Grotesk matches the portfolio's body face.
Section headings range from 44 to 72px. Body copy ranges from 14 to 17px;
small source labels remain supporting content. Values use tabular numerals.

## Layout

The page is capped at 1600px. Fluid gutters run from 20 to 64px. The hero pairs
copy with a product illustration; feature rows have two columns; release facts
have three. At 1000px headings stack above explanatory copy. At 700px the
hero, features, preview and release become single columns. Navigation wraps
without a hidden-menu interaction. Privacy and support use an 860px reading
column and reuse the same fonts, links, focus and color primitives.

## Elevation & Depth

The website is flat, separated by two-pixel rules and contrast. A soft offset
shadow belongs only to the inset native product illustration. Buttons invert
color on hover; no decorative movement is required to read the page.

## Shapes

Square controls and borders define the site. Rounded native illustration cards
are an intentional product context, not the website's container style.
The original wave mark and its SVG are unchanged.

## Components

Primary buttons have an ink ground and white text; secondary buttons are
outlined. Both have a 48px minimum height. Semantic switches have square tracks
and a contrasting moving indicator, with a full clickable text label.
EnergyCard is reused for the hero illustration and interactive preview;
useId keeps their headings unique. The interactive card announces updates.
The keyboard skip link is visually clipped until focused. Teal focus outlines
contrast on light grounds; yellow outlines contrast on the release section.
Reduced Motion removes transitions. Privacy/support work without JavaScript.

## Do's and Don'ts

- Do preserve missing, synthetic and estimated labels in every preview state.
- Do keep native branding changes outside this website specification.
- Do use the developer link to make the relationship to nmapaye.com explicit.
- Don't imply downloads, sign-ups, or release availability before they exist.
- Don't replace truthful product evidence with decorative charts or numbers.
