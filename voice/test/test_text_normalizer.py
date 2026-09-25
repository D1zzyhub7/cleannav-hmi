from cleannav_voice.text_normalizer import TextNormalizer


def test_normalizer_is_conservative_and_removes_common_punctuation():
    normalizer = TextNormalizer()
    assert normalizer.normalize(' 暂停。 ') == '暂停'
    assert normalizer.normalize('继续清扫！') == '继续清扫'
    assert normalizer.normalize('ＡＢＣ   test') == 'abc test'


def test_normalizer_does_not_guess_unknown_text():
    assert TextNormalizer().normalize('清扫最重要的目标') == '清扫最重要的目标'
