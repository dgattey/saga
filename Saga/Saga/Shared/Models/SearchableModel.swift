//
//  SearchableModel.swift
//  Saga
//
//  Created by Dylan Gattey on 7/8/25.
//

/// Every model should conform to this if it's searchable
protocol SearchableModel {
  associatedtype DTOType: SearchableDTO
  func toDTO() -> DTOType
}
