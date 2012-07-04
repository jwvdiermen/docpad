# Necessary
pathUtil = require('path')
balUtil = require('bal-util')
_ = require('underscore')
mime = require('mime')

# Optional
CSON = null
yaml = null

# Local
{Model} = require(__dirname+'/../base')
FileModel = require(__dirname+'/file')


# ---------------------------------
# Document Model

class DocumentModel extends FileModel

	# Model Type
	type: 'document'

	# The parsed file meta data (header)
	# Is a Backbone.Model instance
	meta: null


	# ---------------------------------
	# Attributes

	defaults:

		# ---------------------------------
		# Automaticly set variables

		# The final extension used for our rendered file
		# Takes into accounts layouts
		# "layout.html", "post.md.eco" -> "html"
		extensionRendered: null

		# The file's name with the rendered extension
		filenameRendered: null

		# The MIME content-type for the out document
		contentTypeRendered: null

		# Whether or not we reference other doucments
		referencesOthers: false


		# ---------------------------------
		# Content variables

		# The file meta data (header) in string format before it has been parsed
		header: null

		# The parser to use for the file's meta data (header)
		parser: null

		# The file content (body) before rendering, excludes the meta data (header)
		body: null

		# Have we been rendered yet?
		rendered: false

		# The rendered content (after it has been wrapped in the layouts)
		contentRendered: false

		# The rendered content (before being passed through the layouts)
		contentRenderedWithoutLayouts: null


		# ---------------------------------
		# User set variables

		# Whether or not this file should be re-rendered on each request
		dynamic: false

		# The tags for this document
		tags: null  # Array


	# ---------------------------------
	# Functions

	# Initialize
	initialize: (data,options) ->
		# Prepare
		{@layouts,meta} = options

		# Apply meta
		@meta = new Model()
		@meta.set(meta)  if meta

		# Forward
		super

	# Get Meta
	getMeta: ->
		return @meta

	# To JSON
	toJSON: ->
		data = super
		data.meta = @getMeta().toJSON()
		return data

	# References Others
	referencesOthers: (flag) ->
		flag ?= true
		@set({referencesOthers:flag})
		@

	# Parse data
	# Parses some data, and loads the meta data and content from it
	# next(err)
	parseData: (data,next) ->
		# Reset
		@layout = null
		@getMeta().clear()

		# Super
		super data, =>
			# Content
			content = @get('content')

			# Meta Data
			match = /^\s*([\-\#][\-\#][\-\#]+) ?(\w*)\s*/.exec(content)
			if match
				# Positions
				seperator = match[1]
				a = match[0].length
				b = content.indexOf("\n#{seperator}",a)+1
				c = b+3

				# Parts
				fullPath = @get('fullPath')
				header = content.substring(a,b)
				body = content.substring(c)
				parser = match[2] or 'yaml'

				# Language
				try
					switch parser
						when 'coffee', 'cson'
							CSON = require('cson')  unless CSON
							meta = CSON.parseSync(header)
							@meta.set(meta)

						when 'yaml'
							yaml = require('yaml')  unless yaml
							meta = yaml.eval(header)
							@meta.set(meta)

						else
							err = new Error("Unknown meta parser: #{parser}")
							return next(err)
				catch err
					return next(err)
			else
				body = content

			# Update meta data
			body = body.replace(/^\n+/,'')
			@set(
				header: header
				body: body
				parser: parser
				content: body
				name: @get('name') or @get('title') or @get('basename')
			)

			# Correct data format
			metaDate = @meta.get('date')
			if metaDate
				metaDate = new Date(metaDate)
				@meta.set({date:metaDate})

			# Correct ignore
			ignored = @meta.get('ignored') or @meta.get('ignore') or @meta.get('skip') or @meta.get('draft') or (@meta.get('published') is false)
			@meta.set({ignored:true})  if ignored

			# Handle urls
			metaUrls = @meta.get('urls')
			metaUrl = @meta.get('url')
			@addUrl(metaUrls)  if metaUrls
			@addUrl(metaUrl)   if metaUrl

			# Apply meta to us
			@set(@meta.toJSON())

			# Next
			next()
		@

	# Write the rendered file
	# next(err)
	writeRendered: (next) ->
		# Prepare
		file = @
		fileOutPath = @get('outPath')
		contentRendered = @get('contentRendered')

		# Log
		file.log 'debug', "Writing the rendered file: #{fileOutPath}"

		# Write data
		balUtil.writeFile fileOutPath, contentRendered, (err) ->
			# Check
			return next(err)  if err

			# Log
			file.log 'debug', "Wrote the rendered file: #{fileOutPath}"

			# Next
			return next()

		# Chain
		@

	# Write the file
	# next(err)
	writeSource: (next) ->
		# Prepare
		file = @
		CSON = require('cson')  unless CSON

		# Fetch
		fullPath = @get('fullPath')
		content = @get('content')
		body = @get('body')
		parser = @get('parser')

		# Log
		file.log 'debug', "Writing the source file: #{fullPath}"

		# Adjust
		header = CSON.stringifySync(@meta.toJSON())
		body = body.replace(/^\s+/,'')
		content = "### #{parser}\n#{header}\n###\n\n#{body}"

		# Apply
		@set({header,body,content})

		# Write content
		balUtil.writeFile fileOutPath, content, (err) ->
			# Check
			return next(err)  if err

			# Log
			file.log 'info', "Wrote the source file: #{fullPath}"

			# Next
			next()

		# Chain
		@

	# Normalize data
	# Normalize any parsing we have done, as if a value has updates it may have consequences on another value. This will ensure everything is okay.
	# next(err)
	normalize: (opts={},next) ->
		# Prepare
		{opts,next} = @getActionArgs(opts,next)

		# Super
		super =>
			# Extract
			extensions = @get('extensions')

			# Rendered
			if extensions and extensions.length
				extensionRendered = extensions[0]

			# Apply
			@set({extensionRendered})

			# Next
			next()

		# Chain
		@

	# Contextualize data
	# Put our data into perspective of the bigger picture. For instance, generate the url for it's rendered equivalant.
	# next(err)
	contextualize: (opts={},next) ->
		# Prepare
		{opts,next} = @getActionArgs(opts,next)

		# Super
		super =>
			# Get our highest ancestor
			@getEve (err,eve) =>
				# Check
				return next(err)  if err

				# Fetch
				meta = @getMeta()
				fullPath = @get('fullPath') or null
				basename = @get('basename') or null
				relativeBase = @get('relativeBase') or null
				extensions = @get('extensions')
				extensionRendered = @get('extensionRendered') or null
				url = meta.get('url') or null
				name = meta.get('name') or null
				outPath = meta.get('outPath') or null
				contentTypeRendered = null
				filenameRendered = null

				# Adjust
				if eve
					extensionRendered = eve.get('extensionRendered')
				if basename
					filenameRendered = if extensionRendered then "#{basename}.#{extensionRendered}" else "#{basename}"
				if relativeBase
					url or= if extensionRendered then "/#{relativeBase}.#{extensionRendered}" else "/#{relativeBase}"
				if filenameRendered
					name or= filenameRendered
				outPath or= if @outDirPath then pathUtil.join(@outDirPath,url) else null
				if url
					@addUrl(url)
				if relativeBase
					@removeUrl(if extensions.length then "/#{relativeBase}.#{extensions.join('.')}" else "/#{relativeBase}")

				# Content Types
				if outPath or fullPath
					contentTypeRendered = mime.lookup(outPath or fullPath)

				# Apply
				@set({extensionRendered,filenameRendered,url,name,outPath,contentTypeRendered})

				# Forward
				next()

		# Chain
		@

	# Has Layout
	# Checks if the file has a layout
	hasLayout: ->
		return @get('layout')?

	# Get Layout
	# The the layout object that this file references (if any)
	# next(err,layout)
	getLayout: (next) ->
		# Prepare
		file = @
		layoutId = @get('layout')

		# No layout
		unless layoutId
			return next(null,null)

		# Cached layout
		else if @layout and layoutId is @layout.id
			# Forward
			return next(null,@layout)

		# Uncached layout
		else
			# Find parent
			@emit 'getLayout', {layoutId}, (err,opts) ->
				# Prepare
				{layout} = opts

				# Error
				if err
					return next(err)
				# Not Found
				else unless layout
					debugger
					err = new Error "Could not find the specified layout: #{layoutId}"
					return next(err)
				# Found
				else
					# Update our layout id with the definitive correct one
					file.set('layout': layout.id)

					# Cache our layout
					file.layout = layout

					# Forward
					return next(null,layout)

		# Chain
		@

	# Get Eve
	# Get the most ancestoral layout we have (the very top one)
	# next(err,layout)
	getEve: (next) ->
		if @hasLayout()
			@getLayout (err,layout) ->
				if err
					return next(err,null)
				else
					layout.getEve(next)
		else
			next(null,@)
		@


	# Render extensions
	# next(err,result)
	renderExtensions: (opts,next) ->
		# Prepare
		file = @
		extensions = @get('extensions')
		filename = @get('filename')
		{content,templateData,renderSingleExtensions} = opts
		content ?= @get('body')
		templateData ?= {}
		renderSingleExtensions ?= false

		# Prepare result
		result = content

		# Prepare extensions
		extensionsReversed = []
		if extensions.length is 0 and filename
			extensionsReversed.push(filename)
		for extension in extensions
			extensionsReversed.unshift(extension)

		# If we want to allow rendering of single extensions, then add null to the extension list
		extensionsReversed.push(null)  if extensionsReversed.length is 1 and opts.renderSingleExtensions

		# If we only have one extension, then skip ahead to rendering layouts
		return next(null,result)  if extensionsReversed.length <= 1

		# Prepare the tasks
		tasks = new balUtil.Group (err) ->
			# Forward with result
			return next(err,result)

		# Cycle through all the extension groups and render them
		for extension,index in extensionsReversed[1..]
			# Push the task
			context =
				inExtension: extensionsReversed[index]
				outExtension: extension
			tasks.push context, (complete) ->
				# Prepare
				eventData =
					inExtension: @inExtension
					outExtension: @outExtension
					templateData: templateData
					file: file
					content: result

				# Render
				file.trigger 'render', eventData, (err) ->
					return complete(err)  if err
					result = eventData.content
					return complete()

		# Run tasks synchronously
		tasks.sync()

		# Chain
		@


	# Render Document
	# next(err,result)
	renderDocument: (opts,next) ->
		# Prepare
		file = @
		extension = @get('extensions')[0]
		{opts,next} = @getActionArgs(opts,next)
		{content,templateData} = opts
		content ?= @get('body')
		templateData ?= {}

		# Prepare event data
		eventData = {extension,templateData,file,content}

		# Render via plugins
		file.trigger 'renderDocument', eventData, (err) ->
			# Forward
			return next(err,eventData.content)

		# Chain
		@


	# Render Layouts
	# next(err,result)
	renderLayouts: (opts,next) ->
		# Prepare
		file = @
		{opts,next} = @getActionArgs(opts,next)
		{content,templateData} = opts
		content ?= @get('body')
		templateData ?= {}

		# Grab the layout
		file.getLayout (err,layout) ->
			# Check
			return next(err,content)  if err

			# Check if we have a layout
			if layout
				# Assign the current rendering to the templateData.content
				templateData.content = content

				# Merge in the layout meta data into the document JSON
				# and make the result available via documentMerged
				# templateData.document.metaMerged = _.extend({}, layout.getMeta().toJSON(), file.getMeta().toJSON())

				# Render the layout with the templateData
				layout.render {templateData}, (err,result) ->
					return next(err,result)

			# We don't have a layout, nothing to do here
			else
				return next(null,content)


	# Render
	# Render this file
	# next(err,result,document)
	render: (opts={},next) ->
		# Prepare
		file = @
		contentRenderedWithoutLayouts = null
		fullPath = @get('fullPath')

		# Prepare options
		{opts,next} = @getActionArgs(opts,next)
		opts = _.clone(opts or {})
		opts.actions ?= ['renderExtensions','renderDocument','renderLayouts']

		# Prepare content
		opts.content ?= @get('body')

		# Prepare templateData
		opts.templateData = _.clone(opts.templateData or {})
		opts.templateData.document ?= file.toJSON()
		opts.templateData.documentModel ?= file

		# Prepare result
		# file.set({contentRendered:null, contentRenderedWithoutLayouts:null, rendered:false})

		# Log
		file.log 'debug', "Rendering the file: #{fullPath}"

		# Prepare the tasks
		tasks = new balUtil.Group (err) ->
			# Error?
			if err
				file.log 'warn', "Something went wrong while rendering: #{fullPath}"
				return next(err, opts.content, file)

			# Apply
			contentRendered = opts.content
			contentRenderedWithoutLayouts ?= contentRendered
			rendered = true
			file.set({contentRendered, contentRenderedWithoutLayouts, rendered})

			# Log
			file.log 'debug', "Rendering completed for: #{fullPath}"

			# Success
			return next(null, opts.content, file)

		# Render Extensions Task
		if 'renderExtensions' in opts.actions
			tasks.push (complete) ->
				file.renderExtensions opts, (err,result) ->
					# Check
					return complete(err)  if err
					# Apply the result
					opts.content = result
					# Done
					return complete()

		# Render Document Task
		if 'renderDocument' in opts.actions
			tasks.push (complete) ->
				file.renderDocument opts, (err,result) ->
					# Check
					return complete(err)  if err
					# Apply the result
					opts.content = result
					contentRenderedWithoutLayouts = result
					# Done
					return complete()

		# Render Layouts Task
		if 'renderLayouts' in opts.actions
			tasks.push (complete) ->
				file.renderLayouts opts, (err,result) ->
					# Check
					return complete(err)  if err
					# Apply the result
					opts.content = result
					# Done
					return complete()

		# Fire the tasks
		tasks.sync()

		# Chain
		@

# Export
module.exports = DocumentModel
