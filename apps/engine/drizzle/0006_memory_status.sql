ALTER TABLE `memory` ADD `status` text DEFAULT 'approved' NOT NULL;--> statement-breakpoint
ALTER TABLE `references` ADD `excluded` integer DEFAULT false NOT NULL;--> statement-breakpoint
UPDATE `memory` SET `status` = 'proposed' WHERE `source` = 'reference';