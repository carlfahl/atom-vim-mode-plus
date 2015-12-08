_ = require 'underscore-plus'
{Range} = require 'atom'

class SelectionWrapper
  scope: 'vim-mode-plus'

  constructor: (@selection) ->

  getProperties: ->
    @selection.marker.getProperties()[@scope] ? {}

  setProperties: (newProp) ->
    prop = {}
    prop[@scope] = newProp
    @selection.marker.setProperties prop

  resetProperties: ->
    @setProperties null

  setBufferRangeSafely: (range) ->
    if range
      @setBufferRange(range, {autoscroll: true})

  reverse: ->
    @setReversedState(not @selection.isReversed())

    {head, tail} = @getProperties().characterwise ? {}
    if head? and tail?
      @setProperties
        characterwise:
          head: tail,
          tail: head,
          reversed: @selection.isReversed()

  setReversedState: (reversed) ->
    range = @selection.getBufferRange()
    @setBufferRange range, {autoscroll: true, reversed}

  getRows: ->
    [startRow, endRow] = @selection.getBufferRowRange()
    [startRow..endRow]

  getRowCount: ->
    [startRow, endRow] = @selection.getBufferRowRange()
    endRow - startRow + 1

  selectRowRange: (rowRange) ->
    {editor} = @selection
    [startRow, endRow] = rowRange
    rangeStart = editor.bufferRangeForBufferRow(startRow, includeNewline: true)
    rangeEnd = editor.bufferRangeForBufferRow(endRow, includeNewline: true)
    @setBufferRange rangeStart.union(rangeEnd), {preserveFolds: true}

  # Native selection.expandOverLine is not aware of actual rowRange of selection.
  expandOverLine: ->
    @selectRowRange @selection.getBufferRowRange()

  getTailRange: ->
    {start, end} = @selection.getBufferRange()
    if (start.row isnt end.row) and (start.column is 0) and (end.column is 0)
      [startRow, endRow] = @selection.getBufferRowRange()
      row = if @selection.isReversed() then endRow else startRow
      @selection.editor.bufferRangeForBufferRow(row, includeNewline: true)
    else
      point = @selection.getTailBufferPosition()
      columnDelta = if @selection.isReversed() then -1 else +1
      Range.fromPointWithDelta(point, 0, columnDelta)

  preserveCharacterwise: ->
    prop = @detectCharacterwiseProperties()
    {characterwise} = prop
    endPoint = if @selection.isReversed() then 'tail' else 'head'
    characterwise[endPoint] = characterwise[endPoint].translate([0, -1])
    @setProperties prop

  detectCharacterwiseProperties: ->
    characterwise:
      head: @selection.getHeadBufferPosition()
      tail: @selection.getTailBufferPosition()
      reversed: @selection.isReversed()

  getCharacterwiseHeadPosition: ->
    @getProperties().characterwise?.head

  selectByProperties: (properties) ->
    {head, tail, reversed} = properties.characterwise
    # No problem if head is greater than tail, Range constructor swap start/end.
    @setBufferRange([head, tail])
    @setReversedState(reversed)

  restoreCharacterwise: ->
    unless characterwise = @getProperties().characterwise
      return
    {head, tail, reversed} = characterwise
    [start, end] = if @selection.isReversed()
      [head, tail]
    else
      [tail, head]
    [start.row, end.row] = @selection.getBufferRowRange()
    @setBufferRange([start, end.translate([0, +1])])
    # [NOTE] Important! reset to null after restored.
    @resetProperties()

  # Only for setting autoscroll option to false by default
  setBufferRange: (range, options={}) ->
    options.autoscroll ?= false
    @selection.setBufferRange(range, options)

  isBlockwiseHead: ->
    @getProperties().blockwise?.head

  isBlockwiseTail: ->
    @getProperties().blockwise?.tail

  # Return original text
  replace: (text) ->
    originalText = @selection.getText()
    @selection.insertText(text)
    originalText

  lineTextForBufferRows: (text) ->
    {editor} = @selection
    @getRows().map (row) ->
      editor.lineTextForBufferRow(row)

  translate: (translation, options) ->
    range = @selection.getBufferRange()
    range = range.translate(translation...)
    @setBufferRange(range, options)

swrap = (selection) ->
  new SelectionWrapper(selection)

swrap.setReversedState = (selections, reversed) ->
  selections.forEach (s) ->
    swrap(s).setReversedState(reversed)

swrap.reverse = (selections) ->
  selections.forEach (s) ->
    swrap(s).reverse()

module.exports = swrap
