import sys, numpy as np, cv2
sys.path.insert(0, ".")
import gfx, cards
out = "../promo_work/cards_test/"
c = np.zeros((1080, 1920, 3), np.uint8)
cards.logo_card(c, 1.4, 3.0); cv2.imwrite(out + "logo.png", c)
cards.end_card(c, 3.0, 6.0); cv2.imwrite(out + "end.png", c)
# chip + subtitle over a court-ish gradient
bg = gfx.gradient_bg((120, 200, 230), (40, 120, 90))
b = bg.copy()
chip = cards.feature_chip("发球  SERVE", "hold a direction · toss · hit at the peak", "act_serve.png")
gfx.blit(b, chip, 60, 760, anchor=(0.0, 0.5))
chip2 = cards.feature_chip("拦网 · 扑救", "block at the net, dive to save", "act_block.png", color=gfx.PINK)
gfx.blit(b, chip2, 60, 900, anchor=(0.0, 0.5))
gfx.blit(b, cards.bottom_gradient(), 0, 780, anchor=(0, 0))
sub = cards.subtitle_layer("发球：按住方向选落点，抛球，在最高点按下——时机越准，球越凶。", "Serve: hold a direction to pick your target, toss, and hit at the peak.")
gfx.blit(b, sub, 960, 990, anchor=(0.5, 0.5))
cv2.imwrite(out + "chip_sub.png", b)
print("ok")
