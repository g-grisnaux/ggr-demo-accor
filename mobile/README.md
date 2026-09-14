# ALL Mobile — Mobile RUM

Une app React Native minimale, instrumentée avec le SDK Datadog mobile. Elle
existe pour répondre au besoin « remplacer Firebase sur Android et iOS » avec du
**vrai** Mobile RUM et non des événements fabriqués.

## Pourquoi elle n'est pas construite dans ce dépôt

Ni Xcode ni le SDK Android n'étaient installés sur la machine de préparation :

```
xcode-select -p        -> /Library/Developer/CommandLineTools
xcodebuild             -> absent (nécessite Xcode complet)
xcrun simctl list      -> aucun simulateur
adb / emulator         -> absents
```

Le code est donc écrit et prêt, mais **jamais compilé ni exécuté**. Il faut le
considérer comme non testé jusqu'à la première compilation réussie.

## Prérequis, au choix

**iOS** — Xcode depuis l'App Store (~8 Go), puis :

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo gem install cocoapods
```

**Android** — Android Studio, ou les command-line tools plus une image système,
puis un AVD. Plus léger que Xcode mais les builds Gradle sont lents.

## Configuration

Le SDK a besoin d'une **application RUM distincte** de celle du web. Mélanger
mobile et web dans une seule application RUM rend toute ventilation par
plateforme inutilisable, ce qui est précisément la comparaison demandée.

Crée-la dans Datadog sous **Digital Experience → Add an Application → React
Native**, puis :

```bash
cd mobile
cat > .env.local <<'ENV'
EXPO_PUBLIC_DD_MOBILE_RUM_APP_ID=<application id de l'app RUM mobile>
EXPO_PUBLIC_DD_RUM_CLIENT_TOKEN=<client token>
EXPO_PUBLIC_DD_ENV=ggr-demo-accor-260907
EXPO_PUBLIC_DD_SITE=US1
ENV
```

## Joindre le BFF

Le BFF est un service ClusterIP et rien n'est exposé sur Internet. L'app passe
donc par un port-forward :

```bash
kubectl port-forward -n ggr-demo-accor svc/graphql-bff 8080:8080
```

Le simulateur iOS partage le `localhost` de la machine. L'émulateur Android
atteint l'hôte par `10.0.2.2` — les deux cas sont gérés dans `src/api.js`.

## Lancer

```bash
npm install
npx expo prebuild --clean   # génère les projets ios/ et android/
npm run ios                 # ou: npm run android
```

## Ce que ça produit dans Datadog

| Signal | Où le voir |
|---|---|
| Sessions et vues (`search`, `booking`) | RUM → Sessions, service `all-mobile` |
| Actions (`hotel_search`, `booking_confirmed`) | RUM → Actions |
| Rejets métier comme actions, pas comme erreurs | `business_rejection` avec son `error_code` |
| Erreurs et crash natif symbolisé | RUM → Error Tracking |
| Logs mobiles | Logs, service `all-mobile` |
| **Corrélation mobile → trace backend** | depuis une ressource RUM, saut dans la trace du BFF |

La dernière ligne est l'argument central face à Firebase : `firstPartyHosts`
fait injecter le contexte de trace dans l'appel GraphQL, donc un écran lent se
suit jusqu'au resolver et à l'appel REST en dessous. Firebase s'arrête à la
frontière de l'app.

## Ce qui reste à vérifier après la première compilation

- Que les vues nommées apparaissent bien séparément dans RUM
- Que le crash volontaire remonte avec une stack symbolisée — cela demande
  d'uploader les symboles (`datadog-ci react-native upload`), non fait ici
- Que la corrélation mobile → trace fonctionne à travers le port-forward
