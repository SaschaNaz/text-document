Point = require "../src/point"
HardTabsTransform = require "../src/hard-tabs-transform"
StringLayer = require "../src/string-layer"
TransformLayer = require "../src/transform-layer"
{clip} = TransformLayer::
{expectPositionMappings} = require './spec-helper'

describe "HardTabsTransform", ->
  layer = null

  beforeEach ->
    layer = new TransformLayer(new StringLayer("\tabc\tdefg\t"), new HardTabsTransform(4))

  it "expands hard tab characters to spaces based on the given tab length", ->
    iterator = layer.buildIterator()
    expect(iterator.next()).toEqual(value: "\t   ", done: false)
    expect(iterator.getPosition()).toEqual(Point(0, 4))
    expect(iterator.getSourcePosition()).toEqual(Point(0, 1))

    expect(iterator.next()).toEqual(value: "abc", done: false)
    expect(iterator.getPosition()).toEqual(Point(0, 7))
    expect(iterator.getSourcePosition()).toEqual(Point(0, 4))

    expect(iterator.next()).toEqual(value: "\t", done: false)
    expect(iterator.getPosition()).toEqual(Point(0, 8))
    expect(iterator.getSourcePosition()).toEqual(Point(0, 5))

    expect(iterator.next()).toEqual(value: "defg", done: false)
    expect(iterator.getPosition()).toEqual(Point(0, 12))
    expect(iterator.getSourcePosition()).toEqual(Point(0, 9))

    expect(iterator.next()).toEqual(value: "\t   ", done: false)
    expect(iterator.getPosition()).toEqual(Point(0, 16))
    expect(iterator.getSourcePosition()).toEqual(Point(0, 10))

    expect(iterator.next()).toEqual {value: undefined, done: true}
    expect(iterator.next()).toEqual {value: undefined, done: true}
    expect(iterator.getPosition()).toEqual(Point(0, 16))
    expect(iterator.getSourcePosition()).toEqual(Point(0, 10))

  it "maps target positions to source positions and vice-versa", ->
    symmetrical = (sourcePosition, position) ->
      expect(layer.fromSourcePosition(sourcePosition)).toEqual(position)
      expect(layer.toSourcePosition(position)).toEqual(sourcePosition)

    toSource = (sourcePosition, position, clip) ->
      expect(layer.toSourcePosition(position, clip)).toEqual(sourcePosition)

    symmetrical(Point(0, 0), Point(0, 0))
    toSource(Point(0, 0), Point(0, 1), clip.backward)
    toSource(Point(0, 0), Point(0, 2), clip.backward)
    toSource(Point(0, 0), Point(0, 3), clip.backward)
    toSource(Point(0, 1), Point(0, 1), clip.forward)
    toSource(Point(0, 1), Point(0, 2), clip.forward)
    toSource(Point(0, 1), Point(0, 3), clip.forward)
    symmetrical(Point(0, 1), Point(0, 4))
