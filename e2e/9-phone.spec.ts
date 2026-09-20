import { expect, test } from '@playwright/test';

const IPHONE_UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

test.describe('폰 브라우저: 입력창 확대 · 키보드 높이', () => {
  test('iPhone 에서는 입력창을 눌러도 확대되지 않게 viewport 를 고치고, 보이는 높이를 #root 에 준다', async ({ browser }) => {
    const ctx = await browser.newContext({ userAgent: IPHONE_UA, viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
    const page = await ctx.newPage();
    await page.goto('/');
    await expect(page.getByTestId('tab-bar')).toBeVisible();
    const content = await page.locator('meta[name="viewport"]').getAttribute('content');
    expect(content).toContain('maximum-scale=1');
    expect(content).toContain('width=device-width');
    const height = await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--app-height').trim());
    expect(height).toBe('844px');
    // 시안의 글자 크기는 그대로 (16px 로 키워서 피하지 않는다)
    await page.goto('/#/settings');
    const size = await page.locator('input').first().evaluate((el) => getComputedStyle(el).fontSize);
    expect(Number.parseInt(size, 10)).toBeLessThan(16);
    await ctx.close();
  });

  test('안드로이드 · PC 에서는 손가락 확대를 막지 않는다', async ({ page }) => {
    await page.goto('/');
    const content = await page.locator('meta[name="viewport"]').getAttribute('content');
    expect(content).not.toContain('maximum-scale');
    expect(content).toContain('interactive-widget=resizes-content');
  });
});
