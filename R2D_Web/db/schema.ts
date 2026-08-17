import { index, integer, real, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const bikeReports = sqliteTable(
  "bike_reports",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    category: text("category").notNull(),
    severity: text("severity").notNull().default("caution"),
    description: text("description").notNull(),
    latitude: real("latitude").notNull(),
    longitude: real("longitude").notNull(),
    locationLabel: text("location_label").notNull().default(""),
    source: text("source").notNull().default("r2d_citizen"),
    status: text("status").notNull().default("received"),
    officialStatus: text("official_status").notNull().default("not_submitted"),
    createdAt: integer("created_at").notNull(),
  },
  (table) => [index("bike_reports_created_at_idx").on(table.createdAt)],
);
