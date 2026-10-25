import { Features, Hero, latestRelease, ReleaseNotes, Section, SitePage, site } from "@dylkit/web";

export default async function HomePage() {
  const release = await latestRelease(site);
  return (
    <SitePage>
      <Hero release={release} />
      <Section eyebrow="Your library" title="Everything about the books you read">
        <Features />
      </Section>
      <ReleaseNotes release={release} />
    </SitePage>
  );
}
