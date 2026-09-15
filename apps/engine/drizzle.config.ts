import { defineConfig } from 'drizzle-kit';

export default defineConfig({
  dialect: 'sqlite',
  schema: './src/db/schema.ts',
  out: './drizzle',
  dbCredentials: {
    url: process.env['MADI_DB'] ?? `${process.env['HOME'] ?? '.'}/.madi/madi.db`,
  },
});
