# Hearken website

A standalone, static landing page. It has no build step or package dependencies; serve or upload
the contents of this directory to a static web host. The app icon is included in `assets/` and
is used for the site branding, favicon, and Apple touch icon.

The landing page uses illustrated interface previews, not app screenshots. It links to features
and support rather than advertising an App Store download before a release URL is available.

## GitHub Pages

The [deployment workflow](../.github/workflows/website.yml) publishes only the contents of
this directory. It runs when website files change on `main`, or manually from GitHub Actions.

1. In the repository's **Settings > Pages**, select **GitHub Actions** as the source.
2. Push the workflow to `main` and run **Deploy website to GitHub Pages**.
3. In **Settings > Pages**, set the custom domain to `hearkenstudy.com` before changing DNS.
4. At your DNS provider (currently Bluehost), replace the existing apex (`@`) A record with
   these four A records:

   | Type | Name | Value |
   | --- | --- | --- |
   | A | @ | 185.199.108.153 |
   | A | @ | 185.199.109.153 |
   | A | @ | 185.199.110.153 |
   | A | @ | 185.199.111.153 |
   | CNAME | www | swarren1214.github.io |

   Remove conflicting A, AAAA, or CNAME records for these two hostnames, but preserve unrelated
   records such as MX and TXT records used by email. Do not include `/hearken` in the CNAME value.
   If using IPv6, use GitHub Pages' published AAAA records rather than an old host's addresses.
5. Wait for DNS propagation and GitHub's certificate provisioning, then enable **Enforce HTTPS**
   in **Settings > Pages**. This can take up to 24 hours.

For this Actions-based deployment, GitHub's Pages settings control the custom domain;
an in-repository `CNAME` file is not required.

Consider verifying domain ownership in your GitHub account's **Settings > Pages** using
the TXT record GitHub provides. See GitHub's
[custom domain documentation](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site).

The site includes `privacy.html`, `terms.html`, and `support.html`, linked from the landing-page
footer and the app's About section. Support requests go to `swarren@mail.com`.
