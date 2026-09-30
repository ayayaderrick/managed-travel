# Managed Travel

A travel administration app built on the **ABAP RESTful Application Programming Model (RAP)** using the business object **managed runtime infrastructure**.

The app models a Travel business object with its child entities, and exposes it through two projection layers: one for **processors** who maintain travel requests and one for **approvers** who accept or reject them.

## Business Object

The travel business object is a composition tree:

```
Travel                (root)
└── Booking
    └── BookingSupplement
```

## Features

### Behavior
- **Managed implementation** with standard `create`, `update` and `delete` operations on every entity
- **Behavior pools** (ABAP classes) for Travel, Booking and BookingSupplement
- **Early unmanaged numbering**, backed by a numbering object, for all three entities
- **Actions** on the Travel entity:
  - `copyTravel`
  - `acceptTravel`
  - `rejectTravel`
  - `recalcTotalPrice`
- **Determinations** that calculate values implicitly
- **Validations** on Travel, Booking and BookingSupplement that check that client-provided values are consistent
- **Feature control**
  - Static: defined in the behavior definition for all entities
  - Dynamic: implemented for Travel and Booking

### Projections
- Projection views and behavior projections for the **processor** application
- Projection views and behavior projections for the **approver** application


## Getting Started

### Prerequisites
- An SAP system or ABAP environment that supports RAP (for example SAP BTP ABAP Environment, or S/4HANA on-premise with a recent release)
- [abapGit](https://abapgit.org/) installed on that system
- ABAP Development Tools (ADT) in Eclipse

### Installation
1. In ADT or your system's abapGit, create a new **online repository** pointing to:
   ```
   https://github.com/ayayaderrick/managed-travel.git
   ```
2. Choose or create a package for the objects.
3. **Pull** the repository and activate all objects.
4. Publish the service binding(s) for the processor and approver apps, then open the preview from ADT.

## Development Workflow

Work is done on a `dev` branch and merged to `main` through pull requests, each closing a tracked issue. Commits follow a conventional style such as `feat(bdef): ...`.

## License

Released under the [MIT License](LICENSE). Copyright (c) 2026 Derrick Ayaya.
