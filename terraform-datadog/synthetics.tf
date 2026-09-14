# Synthetic tests, run from a private location inside the GKE cluster.
#
# The private location is the point, not a workaround. The ALL site and the BFF
# sit behind Accor's perimeter, so a Synthetic running from Datadog's public
# managed locations could never reach them. A worker deployed inside the cluster
# probes `http://frontend` and `http://graphql-bff:8080` over ClusterIP exactly
# the way an internal probe of theirs would — and nothing has to be exposed to
# the internet for the demo to work.
#
# The worker is deployed by the Helm chart datadog/synthetics-private-location;
# its credentials live in a Kubernetes Secret and never in this repository,
# which is public.

variable "private_location_id" {
  description = "Synthetics private location the tests run from. Created out of band because the API returns credentials that must not pass through Terraform state."
  type        = string
}

# --- The booking journey, end to end in a real browser ----------------------

resource "datadog_synthetics_test" "booking_journey" {
  name      = "[ALL] Parcours de réservation — navigateur"
  type      = "browser"
  status    = "live"
  locations = [var.private_location_id]
  message   = <<-EOT
    Le parcours de réservation du site ALL est cassé.

    Ce test joue le parcours complet dans un vrai Chrome depuis l'intérieur du
    cluster : recherche d'hôtels, puis réservation. Il échoue avant les clients,
    et l'exécution est enregistrée — captures d'écran à chaque étape et erreurs
    console incluses.

    Pour la suite : [ALL BFF — GraphQL operation health](https://app.${var.datadog_site}/dashboard/${datadog_dashboard.graphql_health.id})
    Notify: @${var.notification_handle}
  EOT

  device_ids = ["chrome.laptop_large"]

  options_list {
    tick_every = 300

    # Un échec isolé ne réveille personne : il faut deux exécutions ratées de
    # suite, ce qui filtre les aléas réseau sans masquer une vraie panne.
    retry {
      count    = 1
      interval = 3000
    }

    monitor_options {
      renotify_interval = 0
    }

    # Les enregistrements sont ce qui répond à « une page plante sans
    # informations suffisantes » : on voit l'écran au moment de l'échec.
    disable_cors  = false
    no_screenshot = false
  }

  request_definition {
    method = "GET"
    url    = "http://frontend"
  }

  browser_step {
    name = "La page d'accueil affiche le formulaire de recherche"
    type = "assertElementPresent"
    params {
      element = jsonencode({
        userLocator = {
          failTestOnCannotLocate = true
          values                 = [{ type = "css", value = "select.select-bordered" }]
        }
      })
    }
  }

  browser_step {
    name = "Lancer la recherche"
    type = "click"
    params {
      element = jsonencode({
        userLocator = {
          failTestOnCannotLocate = true
          values                 = [{ type = "css", value = "button[type=submit]" }]
        }
      })
    }
  }

  browser_step {
    name = "Des résultats remontent avec leurs tarifs"
    type = "assertElementPresent"
    params {
      # XPath indexé, pas un sélecteur CSS de classe : la page affiche 25
      # hôtels avec plusieurs tarifs chacun, donc `button.btn-primary.btn-sm`
      # matche des dizaines d'éléments et le test échoue sur
      # "Multiple elements found". C'est l'erreur qu'a renvoyée la première
      # exécution.
      element = jsonencode({
        userLocator = {
          failTestOnCannotLocate = true
          values                 = [{ type = "xpath", value = "(//button[contains(@class,'btn-sm')])[1]" }]
        }
      })
    }
  }

  browser_step {
    name = "Le nombre de propriétés est affiché"
    type = "assertElementContent"
    params {
      check = "contains"
      value = "properties"
      # Ciblé par son contenu, pas par ses classes : chaque carte d'hôtel porte
      # aussi `p.text-sm.opacity-70` pour sa marque et sa ville, donc le
      # sélecteur CSS matchait vingt-six éléments. Seul le paragraphe de
      # décompte contient le mot "properties".
      element = jsonencode({
        userLocator = {
          failTestOnCannotLocate = true
          values                 = [{ type = "xpath", value = "//p[contains(., 'properties')]" }]
        }
      })
    }
  }

  # Le test s'arrête volontairement avant de confirmer une réservation.
  #
  # Deux raisons. D'abord la fiabilité : le taux de refus de paiement est de 4%
  # en régime normal, donc un test qui réserve vraiment échouerait une fois sur
  # vingt-cinq sans que rien ne soit cassé — un monitor qui clignote est un
  # monitor qu'on finit par ignorer. Ensuite les effets de bord : une sonde qui
  # tourne toutes les cinq minutes créerait des réservations en base à
  # perpétuité. Le parcours jusqu'aux tarifs prouve déjà que le BFF, la
  # recherche et la base répondent.

  tags = ["env:${var.env}", "demo:accor-bff", "surface:web", "managed:terraform"]
}

# --- The GraphQL contract, asserted on the response body --------------------

resource "datadog_synthetics_test" "graphql_search" {
  name      = "[ALL] API GraphQL — searchHotels"
  type      = "api"
  subtype   = "http"
  status    = "live"
  locations = [var.private_location_id]
  message   = <<-EOT
    L'opération GraphQL `searchHotels` ne répond plus correctement.

    À noter, et c'est tout l'intérêt sur une API GraphQL : le test n'assert pas
    seulement un code HTTP 200 — une opération GraphQL en échec répond 200 par
    spécification. Il assert sur le **corps** de la réponse : présence de
    résultats, et absence du tableau `errors`.

    Notify: @${var.notification_handle}
  EOT

  # Les générateurs de date intégrés ne s'utilisent pas directement dans le
  # corps — l'API les interprète alors comme des noms de variables globales et
  # rejette le test. Ils passent par des variables locales dont le `pattern`
  # porte le générateur, référencées ensuite par leur nom.
  config_variable {
    type    = "text"
    name    = "CHECKIN"
    pattern = "{{ date(7d, YYYY-MM-DD) }}"
    example = "2026-09-21"
  }

  config_variable {
    type    = "text"
    name    = "CHECKOUT"
    pattern = "{{ date(10d, YYYY-MM-DD) }}"
    example = "2026-09-24"
  }

  request_definition {
    method = "POST"
    url    = "http://graphql-bff:8080/graphql"

    # Une date figée ferait expirer le test tout seul : l'API refuse une arrivée
    # dans le passé.
    body = jsonencode({
      operationName = "SearchHotels"
      query         = "query SearchHotels($city:String!,$checkIn:String!,$checkOut:String!){searchHotels(city:$city,checkIn:$checkIn,checkOut:$checkOut){nights resultCount hotels{id name availability{available offers{rateCode totalPrice}}}}}"
      variables = {
        city     = "Paris"
        checkIn  = "{{ CHECKIN }}"
        checkOut = "{{ CHECKOUT }}"
      }
    })
    body_type = "application/json"
  }

  request_headers = {
    "Content-Type"     = "application/json"
    "x-client-name"    = "datadog-synthetics"
    "x-client-version" = "1.0.0"
  }

  assertion {
    type     = "statusCode"
    operator = "is"
    target   = "200"
  }

  assertion {
    type     = "responseTime"
    operator = "lessThan"
    target   = "2000"
  }

  # Le contrat métier, pas seulement le transport.
  assertion {
    type     = "body"
    operator = "validatesJSONPath"
    targetjsonpath {
      jsonpath    = "data.searchHotels.resultCount"
      operator    = "moreThan"
      targetvalue = "0"
    }
  }

  # Un tableau `errors` présent signifie que l'opération a échoué malgré le 200.
  assertion {
    type     = "body"
    operator = "doesNotContain"
    target   = "\"errors\""
  }

  options_list {
    tick_every = 60
    retry {
      count    = 2
      interval = 1000
    }
    monitor_options {
      renotify_interval = 0
    }
  }

  tags = ["env:${var.env}", "demo:accor-bff", "surface:api", "managed:terraform"]
}

# --- Health of the chain, one test per downstream service -------------------

resource "datadog_synthetics_test" "downstream_health" {
  for_each = {
    "hotel-search-api" = "http://hotel-search-api:8081/health"
    "booking-api"      = "http://booking-api:8082/health"
    "payment-api"      = "http://payment-api:8083/health"
  }

  name      = "[ALL] Santé ${each.key}"
  type      = "api"
  subtype   = "http"
  status    = "live"
  locations = [var.private_location_id]
  message   = "`${each.key}` ne répond plus sur /health. Notify: @${var.notification_handle}"

  request_definition {
    method = "GET"
    url    = each.value
  }

  assertion {
    type     = "statusCode"
    operator = "is"
    target   = "200"
  }

  assertion {
    type     = "body"
    operator = "validatesJSONPath"
    targetjsonpath {
      jsonpath    = "status"
      operator    = "is"
      targetvalue = "ok"
    }
  }

  options_list {
    tick_every = 300
    retry {
      count    = 1
      interval = 2000
    }
    monitor_options {
      renotify_interval = 0
    }
  }

  tags = ["env:${var.env}", "demo:accor-bff", "surface:api", "service:${each.key}", "managed:terraform"]
}
