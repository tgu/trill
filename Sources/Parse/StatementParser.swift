///
/// StatementParser.swift
///
/// Copyright 2016-2017 the Trill project authors.
/// Licensed under the MIT License.
///
/// Full license text available at https://github.com/trill-lang/trill
///

import AST
import Diagnostics
import Foundation

extension Parser {
  /// While Expression
  ///
  /// while <expr> <braced-expr-block>
  func parseWhileExpr() throws -> WhileStmt {
    try consume(.while)
    let startLoc = sourceLoc
    let condition = try parseExpr()
    let body = try parseCompoundStmt()
    return WhileStmt(condition: condition, body: body,
                     sourceRange: range(start: startLoc))
  }
  
  func parseForLoopExpr() throws -> ForStmt {
    let startLoc = sourceLoc
    try consume(.for)
    var initializer: Stmt? = nil
    if case .semicolon = peek() {
      consumeToken()
    } else  {
      initializer = try parseStatement()
      try consumeAtLeastOneLineSeparator()
    }
    var condition: Expr? = nil
    if case .semicolon = peek() {
      consumeToken()
    } else  {
      condition = try parseExpr()
      try consumeAtLeastOneLineSeparator()
    }
    var incrementer: Stmt? = nil
    if case .leftBrace = peek() {
    } else  {
      incrementer = try parseStatement()
      if [.newline, .semicolon].contains(peek()) { consumeToken() }
    }
    let body = try parseCompoundStmt()
    return ForStmt(initializer: initializer,
                   condition: condition,
                   incrementer: incrementer,
                   body: body,
                   sourceRange: range(start: startLoc))
  }
  
  func parseSwitchExpr() throws -> SwitchStmt {
    let startLoc = sourceLoc
    try consume(.switch)
    let comparator = try parseExpr()
    let terminators: [TokenKind] = [.default, .case, .rightBrace]
    try consume(.leftBrace)
    var cases = [CaseStmt]()
    var defaultBody: CompoundStmt?
    while true {
      if case .case = peek() {
        let tok = consumeToken()
        let expr = try parseExpr()
        let caseRange = range(start: tok.range.start)
        try consume(.colon)
        let bodyStmts = try parseStatements(terminators: terminators)
        let sourceRange = range(start: startLoc)
        let body = CompoundStmt(stmts: bodyStmts, sourceRange: sourceRange)
        cases.append(CaseStmt(constant: expr, body: body, sourceRange: caseRange))
      } else if case .default = peek() {
        consumeToken()
        guard defaultBody == nil else {
          throw Diagnostic.error(ParseError.duplicateDefault,
                                 loc: currentToken().range.start)
            .highlighting(currentToken().range)
        }
        try consume(.colon)
        defaultBody = CompoundStmt(stmts: try parseStatements(terminators: terminators))
      } else {
        throw unexpectedToken()
      }
      if case .rightBrace = peek() {
        consumeToken()
        break
      }
    }
    return SwitchStmt(value: comparator,
                      cases: cases,
                      defaultBody: defaultBody,
                      sourceRange: range(start: startLoc))
  }
  
  func parsePoundDiagnosticExpr() throws -> PoundDiagnosticStmt {
    let startLoc = sourceLoc
    let isError: Bool
    switch peek() {
    case .poundError:
      isError = true
    case .poundWarning:
      isError = false
    default:
      throw unexpectedToken()
    }
    consumeToken()
    guard case .stringLiteral(let value) = peek() else {
      throw unexpectedToken()
    }
    let tok = consumeToken()
    let content = StringExpr(value: value,
                         sourceRange: tok.range)
    return PoundDiagnosticStmt(isError: isError,
                               content: content,
                               sourceRange: range(start: startLoc))
  }
  
  /// If Expression
  ///
  /// if <expr> <braced-expr-block>
  func parseIfExpr() throws -> IfStmt {
    let startLoc = sourceLoc
    try consume(.if)
    var blocks = [(try parseExpr(), try parseCompoundStmt())]
    let elseBody: CompoundStmt?
    if case .else = peek() {
      consumeToken()
      if case .if = peek() {
        let ifExpr = try parseIfExpr()
        blocks += ifExpr.blocks
        elseBody = ifExpr.elseBody
      } else {
        elseBody = try parseCompoundStmt()
      }
    } else {
      elseBody = nil
    }
    return IfStmt(blocks: blocks, elseBody: elseBody,
                  sourceRange: range(start: startLoc))
  }
  
  /// Return Expression
  ///
  /// return <expr>
  func parseReturnStmt() throws -> ReturnStmt {
    let startLoc = sourceLoc
    guard case .return = peek() else {
      throw unexpectedToken()
    }
    consumeToken()
    let val: Expr
    
    // HACK HACK HACK
    let isAtEndOfBlock = [.semicolon, .rightBrace, .case, .default].contains(peek())
    if isAtEndOfBlock || comesAfterLineSeparator() {
      val = VoidExpr()
    } else {
      val = try parseExpr()
    }
    return ReturnStmt(value: val, sourceRange: range(start: startLoc))
  }
  
  /// Break Statement
  ///
  /// break
  func parseBreakStmt() throws -> BreakStmt {
    let startLoc = sourceLoc
    guard case .break = peek() else {
      throw unexpectedToken()
    }
    consumeToken()
    return BreakStmt(sourceRange: range(start: startLoc))
  }
  
  /// Continue Statement
  ///
  /// continue
  func parseContinueStmt() throws -> ContinueStmt {
    let startLoc = sourceLoc
    guard case .continue = peek() else {
      throw unexpectedToken()
    }
    consumeToken()
    return ContinueStmt(sourceRange: range(start: startLoc))
  }
  
  /// Var Assign Decl
  ///
  /// <var-assign-expr> ::= var <identifier> = <expr>
  ///                     | let <identifier> = <expr>
  func parseVarAssignDecl(modifiers: [DeclModifier] = []) throws -> VarAssignDecl {
    let startLoc = sourceLoc
    let mutable: Bool
    if case .var = peek() {
      mutable = true
    } else if case .let = peek() {
      mutable = false
    } else {
      throw unexpectedToken()
    }
    consumeToken()
    let id = try parseIdentifier()
    var rhs: Expr? = nil
    var type: TypeRefExpr?
    if case .colon = peek() {
      consumeToken()
      type = try parseType()
    }
    if case .assignOperator(op: .assign) = peek() {
      consumeToken()
      rhs = try parseExpr()
    }
    guard rhs != nil || type != nil else {
      throw unexpectedToken()
    }
    return VarAssignDecl(name: id,
                         typeRef: type,
                         rhs: rhs,
                         modifiers: modifiers,
                         mutable: mutable,
                         sourceRange: range(start: startLoc))!
  }
}
