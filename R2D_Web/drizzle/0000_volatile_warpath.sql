CREATE TABLE `bike_reports` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`category` text NOT NULL,
	`severity` text DEFAULT 'caution' NOT NULL,
	`description` text NOT NULL,
	`latitude` real NOT NULL,
	`longitude` real NOT NULL,
	`location_label` text DEFAULT '' NOT NULL,
	`source` text DEFAULT 'r2d_citizen' NOT NULL,
	`status` text DEFAULT 'received' NOT NULL,
	`official_status` text DEFAULT 'not_submitted' NOT NULL,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE INDEX `bike_reports_created_at_idx` ON `bike_reports` (`created_at`);