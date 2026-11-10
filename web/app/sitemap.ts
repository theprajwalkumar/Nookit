import type { MetadataRoute } from "next";
import { tools } from "@/lib/catalog";
import { SITE } from "@/lib/site";

export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();
  const staticRoutes: MetadataRoute.Sitemap = [
    { url: SITE.url, lastModified: now, changeFrequency: "weekly", priority: 1 },
    { url: `${SITE.url}/tools`, lastModified: now, changeFrequency: "weekly", priority: 0.9 },
    { url: `${SITE.url}/notch`, lastModified: now, changeFrequency: "monthly", priority: 0.9 },
    { url: `${SITE.url}/pricing`, lastModified: now, changeFrequency: "monthly", priority: 0.8 },
    { url: `${SITE.url}/download`, lastModified: now, changeFrequency: "monthly", priority: 0.6 },
    { url: `${SITE.url}/changelog`, lastModified: now, changeFrequency: "weekly", priority: 0.5 },
    { url: `${SITE.url}/privacy`, lastModified: now, changeFrequency: "yearly", priority: 0.3 },
    { url: `${SITE.url}/terms`, lastModified: now, changeFrequency: "yearly", priority: 0.3 },
  ];

  const toolRoutes: MetadataRoute.Sitemap = tools.map((tool) => ({
    url: `${SITE.url}/tools/${tool.slug}`,
    lastModified: now,
    changeFrequency: "monthly",
    priority: tool.implemented ? 0.7 : 0.5,
  }));

  return [...staticRoutes, ...toolRoutes];
}
