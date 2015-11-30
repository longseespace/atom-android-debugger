{Point, Range, TextEditor, TextBuffer, CompositeDisposable} = require 'atom'
{SelectListView} = require 'atom-space-pen-views'


module.exports =
class VariablesView extends SelectListView
  initialize: () ->
    super

  viewForItem: (item) ->
    "<li><b>#{item.name}</b> = (#{item.type}) #{item.value}</li>"

  getFilterKey: ->
    'name'

  confirmed: (item) ->
    console.log("#{item.name} = (#{item.type}) #{item.value}")

  cancelled: ->
    console.log("This view was cancelled")