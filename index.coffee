#!/usr/bin/env coffee

_           = require("lodash")
fs          = require("fs")
path        = require("path")
exec        = require("child_process").exec
yaml        = require("js-yaml")
moment      = require("moment")
numeral     = require("numeraljs")
wkhtmltopdf = require("wkhtmltopdf")
handlebars  = require("handlebars")

translation = {}

# Helper functions
setLanguage = (lang) ->
  moment.locale(lang)
  try
    numeral.language(lang, require("numeraljs/languages/#{lang}"))
  catch e
  numeral.language(lang)
  translation = require(path.join(data.meta.destination.assetsFolder, "languages", "#{lang}.json"))
  #translation = require("./languages/#{lang}.json")

replaceExtname = (filename, newExtname) ->
  return filename.replace(new RegExp(path.extname(filename).replace(/\./g, "\\."), "g"), newExtname)

roundCurrency = (value) ->
  if isNaN(value)
    value = 0
  return parseFloat(value.toFixed(2))

sum = (items) ->
  items.reduce(((r, a) -> r + a), 0)

calculateNet = (items) ->
  return sum(_.pluck(items, "net_value"))

calculateDiscount = (items) ->
  return sum(_.pluck(items, "net_discount"))

calculateDiscountIncl = (items) ->
  return sum(_.pluck(items, "discountIncl"))

calculateTotal = (items) ->
  return sum(_.pluck(items, "total_value"))


# Default language setting
#setLanguage("de")

# Business logic transformation
transformData = (data) ->

  _.defaults(data,
    order: {}
    receiver: {}
    items: []
    intro_text: ""
    outro_text: ""
  )

  data.order.language ?= "de"
  setLanguage(data.order.language)

  data.meta.assets = path.join(data.meta.destination.assetsFolder)

  data.order.orderDate ?= new Date()
  data.order.template ?= "default"
  data.order.location ?= data.sender.town
  data.order.currency ?= "€"
  data.order.totalNet ?= 0
  data.order.totalIncl ?= 0
  data.order.totalTax ?= []

  data.items = data.items.map((item) ->

    item = _.defaults(item,
      quantity: 1
      tax_rate: 0
      taxRate: 0
      discount_percentage: 0
      discountPercentage: 0
      discountAmount: 0
      discount_amount: 0
      discountAmountIncl: 0
      discount_amountIncl: 0
      type: 'd'
    )

    if not item.title?
      item.title = ""
      #throw new Error("An invoice item needs a title.")

    if not item.price?
      item.price = 0
      #throw new Error("An invoice item needs a price.")

    if not item.discountPercentage
      item.discountPercentage = 0

    if not item.discountAmount
      item.discountAmount = 0

    if not item.discountAmountIncl
      item.discountAmountIncl = 0

    #if _.isString(item.quantity)
    #  item.quantity = (new Function("return #{item.quantity.replace(/\#/g, "//")};"))()
    
    item.tax_rate = item.taxRate
    item.discount_percentage = parseFloat(item.discountPercentage)
    #item.quantity = parseInt(item.quantity)
    #item.quantity = Math.ceil(item.quantity)
    item.net_discount = (item.quantity * item.price) * (item.discount_percentage / 100)
    item.net_discount = item.net_discount + (item.quantity * item.discountAmount)
    item.net_discount = item.net_discount + (item.quantity * (item.discountAmountIncl / (1 + (item.tax_rate / 100))))
    item.discountIncl = item.net_discount * (1 + item.tax_rate / 100)
    item.net_value = (item.quantity * item.price) * (1 - (item.discount_percentage / 100)) - (item.quantity * item.discountAmount) - (item.quantity * (item.discountAmountIncl / (1 + (item.tax_rate / 100))))
    item.tax_value = item.net_value * (item.tax_rate / 100)
    item.total_value = item.net_value * (1 + item.tax_rate / 100)
    item.priceIncl = (item.total_value + item.discountIncl) / item.quantity
    #item.net_value = roundCurrency(item.net_value)
    #item.tax_value = roundCurrency(item.tax_value)
    #item.total_value = roundCurrency(item.total_value)
    return item
  )

  data.totals =
    net: data.order.totalNet
    discount: calculateDiscount(data.items)
    discountIncl: calculateDiscountIncl( data.items )
    total: data.order.totalIncl
    tax: data.order.totalTax.map((tx) ->
        return {
          rate: tx.tax,
          total: tx.value
        }
      )

  data


# Process arguments
inFilename = process.argv[2]
outFilename = replaceExtname(inFilename, ".pdf")

data = yaml.safeLoad(fs.readFileSync(inFilename, "utf8"))
data = transformData(data)

# Default language setting
#setLanguage("de")


templateFolder = data.meta.template.folder

tmpFilename = "#{templateFolder}/#{"xxxx-xxxx-xxxx".replace(/x/g, -> ((Math.random() * 16) | 0).toString(16))}.html"

# Prepare rendering
handlebars.registerHelper("plusOne", (value) ->
  return value + 1
)
handlebars.registerHelper("number", (value) ->
  return numeral(value).format("0[.]0[00]")
)
handlebars.registerHelper("money", (value) ->
  return "#{numeral(value).format("0,0.00")} #{data.order.currency}"
)

handlebars.registerHelper("moneyRound", (value) ->
  return "#{numeral(value).format("0,0.00")}"
)

handlebars.registerHelper("percent", (value) ->
  return numeral( value / 100 ).format("0.00 %")
)
handlebars.registerHelper("fullPercent", (value) ->
  return numeral(value / 100).format("0 %")
)

handlebars.registerHelper("date", (value) ->
  return moment(value).format("LL")
)
handlebars.registerHelper("lines", (options) ->
  contents = options.fn()
  contents = contents.split(/<br\s*\/?>/)
  contents = _.compact(contents.map((a) -> a.trim()))
  contents = contents.join("<br>")
  return contents
)
handlebars.registerHelper("pre", (contents) ->
  if not contents == null
    return new handlebars.SafeString(contents.split(/\n/).map((a) -> handlebars.Utils.escapeExpression(a)).join("<br>"))
  else
    return ''
)
handlebars.registerHelper("t", (phrase) ->
  return translation[phrase] ? phrase
)

# Rendering
args = {
  output: "#{data.meta.destination.pdf}",
  marginLeft: "0mm",
  marginRight: "0mm",
}
#-- Header

if !!data.meta.destination.header
  args.headerHtml = "file:///#{data.meta.destination.header}"
  template = handlebars.compile(fs.readFileSync("#{data.meta.template.header}", "utf8"))
  fs.writeFileSync(data.meta.destination.header, template(data), "utf8")
# -- Footer
if !!data.meta.destination.footer
  args.footerHtml = "file:///#{data.meta.destination.footer}"
  template = handlebars.compile(fs.readFileSync("#{data.meta.template.footer}", "utf8"))
  fs.writeFileSync(data.meta.destination.footer, template(data), "utf8")
#-- Body
template = handlebars.compile(fs.readFileSync("#{data.meta.template.body}", "utf8"))
fs.writeFileSync(data.meta.destination.body, template(data), "utf8")

  
wkhtmltopdf("file:///#{data.meta.destination.body}", args, (err) ->
  if err
    console.error("Error creating #{data.meta.destination.pdf}")
    console.error(err)
  else
    console.log("Created #{data.meta.destination.pdf}")
  
  #fs.unlinkSync(tmpFilename)
)
