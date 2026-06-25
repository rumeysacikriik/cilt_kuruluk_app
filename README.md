# cilt_kuruluk_app

Görüntü işleme tekniğiyle cilt ve dudak kuruluğu (Xerosis) analizi yapan, yapay zeka destekli ve kullanıcı dostu arayüz odaklı bir mobil sağlık asistanı projesidir.

## Projenin Amacı ve Konusu
Cilt ve dudak kuruluğu, günlük hayatta sıkça yaşanan ancak derecesi ve ciddiyeti insanlar tarafından tam olarak kestirelemeyen bir durumdur. Bu proje; kullanıcıların ev konforunda, sadece bir fotoğrafla ciltlerinin kuruluk durumunu takip edebilecekleri pratik, hızlı ve güvenilir bir mobil asistan sunmak amacıyla geliştirilmiştir.

---

## Teknik Altyapı & Çalışma Mantığı
Uygulama, derin öğrenme teknolojisi ile mobil platformu bir araya getirerek senkronize bir şekilde çalışır:
* **Yapay Zeka & Derin Öğrenme:** Cilt ve dudak fotoğraflarındaki kuruluk belirtilerini (çatlama, soyulma, renk değişimi) ayırt edebilmek amacıyla arka planda **MobileNetV2** mimarisi ve **TensorFlow/Keras** altyapısı kullanılmıştır.
* **Mobil Platform:** Yapay zeka modelinin kullanıcıyla buluştuğu frontend ve uygulama katmanı **Flutter (Dart)** ile geliştirilmiş olup, uygulamanın cross-platform (Android & iOS) olarak akıcı çalışması sağlanmıştır.

### Kullanıcı Akışı (User Flow)
1. **Fotoğraf Girişi:** Kullanıcı uygulama içi kamerayı kullanarak anlık fotoğraf çeker veya galerisinden bir görsel yükler.
2. **Model Analizi:** Yüklenen görsel, entegre edilen görüntü sınıflandırma modeli tarafından saniyeler içinde işlenir.
3. **Analiz Sonucu:** Kullanıcıya cildinin kuruluk seviyesini net bir şekilde bildiren ve buna yönelik basit asistan geri bildirimleri sunan bir sonuç ekranı gösterilir.

---

## Tasarım Yaklaşımı & UI/UX Kararları
Sağlık ve medikal odaklı bir uygulama olmasından dolayı, kullanıcılara güven ve sakinlik hissi veren, karmaşadan uzak bir tasarım dili benimsenmiştir:
* **Soft Renk Paleti:** Kullanıcıyı yormayacak ve paniğe sevk etmeyecek temiz bir medikal tema için yumuşak krem (`#E1DDD4`) ve pastel tonlar tercih edilmiştir.
* **Minimalist ve Esnek Arayüz (Responsive UI):** Ekrandaki tüm butonlar, menüler ve yönlendirmeler olabildiğince sade tutulmuştur. Keskin hatlar yerine yumuşatılmış/oval kenarlar kullanılarak görsel bütünlük ve modern bir Layout yapısı sağlanmıştır.
