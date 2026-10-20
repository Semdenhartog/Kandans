# Extra Android-bestanden

De map `android/` wordt in de cloud elke keer opnieuw gemaakt (`flutter create`).
Deze bestanden worden daarna door de workflow erin gezet:

- `kotlin/BestMomentWidget.kt` → widget "Beste moment vandaag" voor je startscherm
- `res/...` → opmaak van de widget

De app vult de widget via het pakket `home_widget` (zie `lib/data/services/home_widget_service.dart`).
