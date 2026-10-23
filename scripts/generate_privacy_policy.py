#!/usr/bin/env python3
"""Build the offline policy; update public copies only when explicitly requested."""
# [01] Keep one reviewed policy source; the app can be built and checked without any website files.
from pathlib import Path
from datetime import date
import argparse
import html
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / 'DigitalFootprintExplorer/iosApp/Configuration/PrivacyPolicyContent.json'


# [02] Use the same escaping rules for policy text so quotes and accents remain readable in the app.
def swift_string(value):

    return json.dumps(value, ensure_ascii=False)


# [03] The app copy is the default. Website copies are available only when their separate publication is requested.
def outputs(document, *, include_web=False):
    sections = document['sections']
    updated = date.fromisoformat(document['revision']).strftime('%d %B %Y').lstrip('0')
    policy_lines = [f"# {document['app_name']}", '', f"## {document['title']}", '', f"Last updated: {updated}", '']
    policy_lines += sum(([paragraph, ''] for paragraph in document['introduction']), [])
    for section in sections:
        policy_lines += [f"### {section['title']}", '']
        policy_lines += sum(([paragraph, ''] for paragraph in section['paragraphs']), [])
    markdown = '\n'.join(policy_lines)
    body = '\n'.join(f'<p>{html.escape(paragraph)}</p>' for paragraph in document['introduction'])
    for section in sections:
        body += f'\n<section aria-labelledby="{section["id"]}"><h2 id="{section["id"]}">{html.escape(section["title"])}</h2>\n'
        body += '\n'.join(f'<p>{html.escape(paragraph)}</p>' for paragraph in section['paragraphs'])
        body += '\n</section>'
    web = f'''<!doctype html>
<!-- [01] Generated from the reviewed policy source; change that source to keep the app and web text together. -->
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="How Digital Footprint Explorer handles your local history and optional Screen Time access.">
  <title>{html.escape(document['title'])} — {html.escape(document['app_name'])}</title>
  <style>
    /* [02] Readable colours follow the system choice, while print keeps a clear white page. */
    :root {{ color-scheme: light dark; --text: #17251d; --muted: #45564a; --surface: #fff; --line: #d9e2dc; }}
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; background: var(--surface); color: var(--text); font: 1rem/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }}
    main {{ max-width: 48rem; margin: auto; padding: clamp(1.25rem, 4vw, 3rem); }}
    header {{ padding-bottom: 1.25rem; border-bottom: 1px solid var(--line); }}
    .app-name {{ margin-bottom: .5rem; color: var(--muted); }}
    h1 {{ font-size: clamp(1.8rem, 4vw, 2.5rem); line-height: 1.2; margin: .5rem 0 1rem; }}
    h2 {{ font-size: 1.25rem; line-height: 1.35; margin: 2rem 0 .75rem; }}
    p {{ margin: .75rem 0; overflow-wrap: anywhere; }}
    .updated {{ color: var(--muted); }}
    a {{ color: #17613b; text-underline-offset: .2em; }}
    a:focus-visible {{ outline: 3px solid currentColor; outline-offset: 4px; }}
    footer {{ margin-top: 2.5rem; padding-top: 1.25rem; border-top: 1px solid var(--line); }}
    @media (prefers-color-scheme: dark) {{ :root {{ --text: #f0f7f2; --muted: #c2d0c6; --surface: #142019; --line: #405247; }} a {{ color: #a2e4ba; }} }}
    @media print {{ :root {{ --text: #000; --muted: #333; --surface: #fff; --line: #ccc; }} main {{ max-width: none; padding: 0; }} h2 {{ break-after: avoid; }} }}
  </style>
</head>
<body>
<!-- [03] Keep the revision beside the policy so readers know which privacy choices they are reviewing. -->
<main>
  <header>
    <p class="app-name">{html.escape(document['app_name'])}</p>
    <h1>{html.escape(document['title'])}</h1>
    <p class="updated">Last updated: <time datetime="{document['revision']}">{html.escape(updated)}</time></p>
  </header>
  {body}
  <footer><a href="mailto:{html.escape(document['contact_email'])}">Email the {html.escape(document['contact_name'])}</a></footer>
</main>
</body>
</html>
'''
    swift_sections = []
    for section in sections:
        paragraphs = ',\n                '.join(swift_string(paragraph) for paragraph in section['paragraphs'])
        swift_sections.append(f'''        PrivacyPolicySection(
            id: {swift_string(section['id'])},
            title: {swift_string(section['title'])},
            paragraphs: [
                {paragraphs}
            ]
        )''')
    intro = ',\n        '.join(swift_string(paragraph) for paragraph in document['introduction'])
    source = f'''// [01] Generated from the reviewed policy in iosApp/Configuration/PrivacyPolicyContent.json. Edit that source to update this local copy.
import Foundation

// [02] Stable section names keep the privacy page in a clear, predictable reading order.
struct PrivacyPolicySection: Identifiable {{
    let id: String
    let title: String
    let paragraphs: [String]
}}

// [03] Ship a local copy so privacy choices remain available without an internet connection.
enum PrivacyPolicyContent {{
    static let appName = {swift_string(document['app_name'])}
    static let title = {swift_string(document['title'])}
    static let revision = {swift_string(document['revision'])}
    static let updatedText = {swift_string('Last updated: ' + updated)}
    static let contactURL = URL(string: {swift_string('mailto:' + document['contact_email'])})!
    static let introduction = [
        {intro}
    ]
    static let sections = [
{',\n'.join(swift_sections)}
    ]
}}
'''
    generated = {
        ROOT / 'DigitalFootprintExplorer/iosApp/iosApp/PrivacyPolicyContent.swift': source,
    }
    if include_web:
        generated.update({
            ROOT / 'docs/privacy-policy.md': markdown,
            ROOT / 'docs/privacy-policy.html': web,
        })
    return generated


# [04] Reject incomplete policy details before writing any copy. Check mode reports old copies without replacing them.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Verify the selected copies without rewriting them.')
    parser.add_argument('--include-web', action='store_true', help='Also generate or verify the separate HTML and Markdown website copies.')
    args = parser.parse_args()
    document = json.loads(CONTENT.read_text())
    if document['schema_version'] != 1:
        raise ValueError('Unsupported policy schema')
    ids = [section['id'] for section in document['sections']]
    if len(set(ids)) != len(ids) or not ids:
        raise ValueError('Policy sections need unique, stable IDs')
    if not document.get('contact_name', '').strip():
        raise ValueError('A public team contact name is required')
    if not document['contact_email'] or '@' not in document['contact_email']:
        raise ValueError('A real project contact is required')
    stale = []
    for path, content in outputs(document, include_web=args.include_web).items():
        if args.check:
            if not path.is_file() or path.read_text() != content:
                stale.append(str(path.relative_to(ROOT)))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
    if stale:
        print('Policy copies are out of date: ' + ', '.join(stale), file=sys.stderr)
        return 1
    print('Policy copies agree.' if args.check else 'Policy copies generated.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
