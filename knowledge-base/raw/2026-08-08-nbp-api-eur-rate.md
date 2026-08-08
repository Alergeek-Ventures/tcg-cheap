# NBP EUR exchange-rate API observation

- Collected: 2026-08-08
- Authority: official NBP documentation and live HTTPS API response
- Status: immutable, time-specific capture; a later response may differ

## Official sources

- API documentation: https://api.nbp.pl/en.html
- HTTPS instruction: https://nbp.pl/en/statistic-and-financial-reporting/rates/the-instruction-how-to-retrieve-currency-exchange-rates-from-the-nbp-website/

## Exact observations

- The official HTTPS instruction says HTTPS is mandatory for NBP API requests from 2025-08-01.
- The latest published Table A EUR endpoint is `https://api.nbp.pl/api/exchangerates/rates/a/eur/`.
- The endpoint returns the latest published Table A average (`mid`) rate, rather than necessarily a same-day publication.
- Live response observed on 2026-08-08: table `A`, code `EUR`, publication number `152/A/NBP/2026`, effective date `2026-08-07`, `mid` `4.3010`.
- HTTP 404 means that no data exists for the requested today/date. Historical date queries are capped at 93 days.
- No published numeric request quota was found in the reviewed official documentation. This is not evidence that no operational limit exists.

All observations above are specific to the collection date and reviewed documentation at that time.

## JSON excerpt

```json
{
  "table": "A",
  "currency": "euro",
  "code": "EUR",
  "rates": [
    {
      "no": "152/A/NBP/2026",
      "effectiveDate": "2026-08-07",
      "mid": 4.3010
    }
  ]
}
```

## Implementation consequence

The backend uses one canonical NBP A EUR/PLN observation per effective date, retains history, refreshes same-date records, and treats weekends/holidays as carry-forward through the latest published rate. The provider request is HTTPS-only and uses the current endpoint above. No NBP request is made from a LiveView or normal request path.
