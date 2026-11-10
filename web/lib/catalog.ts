import catalog from "./catalog.json";

export type CategoryId =
  | "video"
  | "audio"
  | "images"
  | "docs"
  | "text"
  | "files"
  | "mac"
  | "developer";

export interface Tool {
  slug: string;
  name: string;
  category: CategoryId;
  symbol: string;
  implemented: boolean;
  tagline: string;
  description: string;
}

export interface Category {
  id: CategoryId;
  name: string;
  blurb: string;
}

export interface NotchModule {
  id: string;
  name: string;
  group: string;
  symbol: string;
  implemented: boolean;
  tagline: string;
  shortcut: string;
  description: string;
}

export interface Product {
  name: string;
  tagline: string;
  description: string;
  price: number;
  compareAt: number;
  currency: string;
  macsPerLicense: number;
  minOS: string;
  site: string;
  support: string;
}

interface Catalog {
  product: Product;
  categories: Category[];
  tools: Tool[];
  notchModules: NotchModule[];
  counts: {
    tools: number;
    notch: number;
    implementedTools: number;
    byCategory: Record<string, number>;
  };
}

export const catalogData = catalog as unknown as Catalog;
export const product = catalogData.product;
export const categories = catalogData.categories;
export const tools = catalogData.tools;
export const notchModules = catalogData.notchModules;
export const counts = catalogData.counts;

export const readyTools = tools.filter((t) => t.implemented);
export const roadmapTools = tools.filter((t) => !t.implemented);
export const readyNotch = notchModules.filter((m) => m.implemented);

export function getTool(slug: string): Tool | undefined {
  return tools.find((t) => t.slug === slug);
}

export function getCategory(id: string): Category | undefined {
  return categories.find((c) => c.id === id);
}

export function toolsInCategory(id: string): Tool[] {
  return tools.filter((t) => t.category === id);
}

export function relatedTools(tool: Tool, limit = 3): Tool[] {
  const same = tools.filter(
    (t) => t.category === tool.category && t.slug !== tool.slug,
  );
  const ready = same.filter((t) => t.implemented);
  const rest = same.filter((t) => !t.implemented);
  return [...ready, ...rest].slice(0, limit);
}

export function toolCounts(): { total: number; ready: number; roadmap: number } {
  return {
    total: tools.length,
    ready: readyTools.length,
    roadmap: roadmapTools.length,
  };
}

export function searchTools(query: string): Tool[] {
  const q = query.trim().toLowerCase();
  if (!q) return tools;
  const terms = q.split(/\s+/);
  return tools
    .map((tool) => {
      const haystack = [
        tool.name,
        tool.tagline,
        tool.description,
        getCategory(tool.category)?.name ?? "",
      ]
        .join(" ")
        .toLowerCase();
      const score = terms.reduce((acc, term) => {
        if (tool.name.toLowerCase().startsWith(term)) return acc + 6;
        if (tool.name.toLowerCase().includes(term)) return acc + 4;
        if (haystack.includes(term)) return acc + 1;
        return acc - 10;
      }, 0);
      return { tool, score };
    })
    .filter((r) => r.score > 0)
    .sort((a, b) => b.score - a.score)
    .map((r) => r.tool);
}

export const categoryMeta: Record<
  CategoryId,
  { tint: string; tintSoft: string; icon: string }
> = {
  video: { tint: "#FF5A1F", tintSoft: "#FFE4D6", icon: "play" },
  audio: { tint: "#B4488F", tintSoft: "#F7E0F0", icon: "wave" },
  images: { tint: "#2F7FD6", tintSoft: "#DCEBFB", icon: "image" },
  docs: { tint: "#C2413C", tintSoft: "#F8E0DE", icon: "doc" },
  text: { tint: "#17795A", tintSoft: "#DDF4EA", icon: "text" },
  files: { tint: "#8A6A1F", tintSoft: "#F4EBCF", icon: "folder" },
  mac: { tint: "#4C5566", tintSoft: "#E6E9EF", icon: "mac" },
  developer: { tint: "#5A4BC4", tintSoft: "#E6E2FA", icon: "code" },
};
