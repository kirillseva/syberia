#' Fetch a syberia project director relative a filename.
#'
#' @param filename character. Some in a syberia project.
#' @return the director object for the syberia project.
#' @export
#' @examples
#' \dontrun{
#'   # Pretend you have the file blah/foo.R in your syberia project ~/proj.
#'   syberia_projects('~/proj/blah/foo.R')
#'   # Now we have the director object for the ~/proj syberia project.
#' }
syberia_project <- local({
  # A cache of directors for the existent syberia projects
  syberia_projects <- list()

  function(filename) {
    if (!(is.character(filename) && length(filename) == 1)) {
      stop("To fetch a syberia project, you must specify a file path ",
           "(a character vector of length 1). Instead we got a ",
           class(filename)[1], if (is.character(filename)) paste0(
           ' of length ', length(filename)))
    }
    # TODO: (RK) Don't go through syberia_root here
    root <- normalizePath(syberia_root(filename))
    if (!is.element(root, names(syberia_projects)))
      syberia_projects[[root]] <<- bootstrap_syberia_project(director(root, 'syberia'))
    syberia_projects[[root]]
  }
})

#' Bootstrap a syberia project by setting up its director object.
#'
#' The initial parsers that are derived from the syberia configuration
#' directory (\code{"config/"}) will be added to the director object here.
#' In particular, the \code{"config/routes.R"} file should specify the 
#' controllers for various resource types, which will reside in 
#' \code{"lib/controllers"} and be simple files with one function without
#' any arguments. This function will have the following present
#' when executed:
#'
#' \itemize{
#'   \item{"resource"}{The name of the resource (basically, the filename
#'     without the .R extension). If the resource is so-called an idempotent
#'     resource, then this will be the non-idempotent version. An
#'     idempotent resource is a file which is located in a directory whose
#'     name is the same as the filename without extension.
#'    
#'     For example, \code{"models/infection/infection.R"} is an idempotent resource
#'     because the \code{"infection.R"} file is present in the \code{"infection"}
#'     directory and--ignoring file extension--they are identical. This kind of
#'     convention allows any file in a syberia project to have helpers functions
#'     that better help you structure your files. For example, if
#'     \code{"infection.R"} needs to reference some long list of static
#'     variable names, they can can be placed in \code{"models/infection/const.R"}
#'     and included in \code{infection.R} using the \code{define} function
#'     from the Ramd package.
#'
#'     The \code{resource} key will be the filename without its extension if it
#'     is not an idempotent resource (so \code{"models/airtraffic.R"} will have
#'     key \code{"models/airtraffic"}). On the other hand, an idempotent
#'     resource will have key its residing directory so
#'     (\code{"models/pollution/pollution.R"} will have key
#'     \code{"models/pollution"}).}
#'
#'  \item{"input"}{When an R file is sourced through the \code{base::source}
#'     function, it leaves a trail we can follow. This is because \code{source}
#'     takes a second argument \code{local} (see the documentation for
#'     \code{base::source}) which allows you to provide an environment in which
#'     all execution of a given file will occur. Thus, if we have a file
#'     that has the body \code{test <- 1; string <- 'hello'}, using this trick
#'     we can construct an environment that has \code{test = 1} and
#'     \code{string = 'hello'}.
#'
#'     The \code{input} that is available to the controller is precisely
#'     this environment.}
#'
#'   \item{"output"}{When an R file is sourced through the \code{base::source}
#'     function, its last executed expression is available in the return
#'     value's \code{$value} key. Thus, if you had a file \code{"model.R"} with code
#'     \code{column <- 'Sepal.Length'; lm(iris$Sepal.Width ~ iris[[column]])}
#'     then we can access the \code{lm} model using \code{source('model.R')$value}.
#'     
#'     This "file return value" is precisely the \code{output} that is available
#'     to the controller for a resource.}
#'
#'   \item{"resource_body"}{The source code (as a string) of the resource is
#'     available as \code{resource_body} in the controller.}
#'
#'   \item{"director"}{The director object of the enclosing syberia project is
#'     available through the \code{director} local variable in controller.
#'
#'     For more information on this, see the \code{director} package.}
#'
#' }
#'
#' The \code{config/routes.R} file in your syberia project should look something
#' like this:
#'
#' \code{list('lib/classifiers' = 'classifier',
#'            'data'            = 'data')}
#'
#' where we have two kinds of resources: classifiers and data sources.
#' 
#' It is up to you how to define what these resources "do". The
#' \code{lib/classifiers} and \code{data} directories (in the root of your
#' syberia project) can have arbitrary code, and the \code{resource},
#' \code{input}, and \code{output} (like in the list above) are made available
#' to the controller.
#'
#' The return value of a controller will be the final result of a user
#' attempting to load a resource. For example, if we had the controller
#' \code{"lib/controllers/classifier.R"} with:
#'
#' \code{function() {
#'   classifier <- list(train = input$train, predict = input$predict)
#'   class(classifier) <- 'simpleClassifier'
#'   classifier
#' }}
#'
#' then we could define a classifier object like the one generated above
#' by placing a \code{train} and \code{predict} function in a file
#' \code{"simple.R"} in the \code{lib/classifiers} directory.
#'
#' Then, if we have our syberia project, say
#'    \code{proj <- syberia_project('some/directory')}
#' we could load this object with
#'    \code{simple_classifier <- proj$resource('lib/classifiers/simple')}
#' and have an object that we can call \code{simple_classifier$train(...)}
#' and \code{simple_classifier$predict} on.
#'
#' TODO: (RK) Explain why this is better than just random files.
#'
#' @param project director. The syberia director object to boostrap.
bootstrap_syberia_project <- function(director) {
  routes_path <- file.path('config', 'routes')
  if (director$exists(routes_path)) {
    director$register_parser(routes_path, routes_parser, overwrite = TRUE)
  }
  director
}

#' A director parser for parsing a routes file.
#'
#' A routes file (in \code{"config/routes.r"} relative to the syberia project)
#' should contain a list whose names give the route prefixes and whose
#' values are the controller names for parsing resources that begin with
#' these prefixes. For example, if the file contains
#' 
#' \code{list('models' = 'models', 'lib/adapters' = 'adapters')}
#'
#' then files in the directory \code{"models"} (relative to the root of the
#' syberia project) will be processed by the \code{"models"} controller
#' and the files in the directory \code{"lib/adapters"} will be
#' processed by the \code{adapters} controller. There should be files
#' \code{"adapters.R"} and \code{"models.R"} in the \code{"lib/controllers"}
#' directory containing only a single function. The function (the heart of
#' the controller) will be applied to files sourced in the respective
#' resource directory (\code{"models"} or \code{"lib/adapters"}).
#' See the function \code{bootstrap_syberia_project} to understand what
#' things are available in a controller function.
#'
#' @seealso \code{bootstrap_syberia_project}.
routes_parser <- function() {
  error <- function(...) {
    stop("In your ", director:::colourise("config/routes.R", "red"), " file in the ",
         "syberia project at ", sQuote(director:::colourise(director$.root, 'blue')),
         ' ', ..., call. = FALSE)
  }

  if (!is.list(output)) {
    error("you should return a list (put it at the end of the file). ",
         "Currently, you have something of type ", sQuote(class(output)[1]), ".")
    # TODO: (RK) More informative message here.
  }
  if (length(output) > 0 &&
      (any(sapply(names(output), function(n) !isTRUE(nzchar(n)))) ||
       length(unique(names(output))) != length(output))) {
    error(" your list of routes needs to have unique prefixes.")
    # TODO: (RK) Provide better information about name duplication or missing names.
  }

  # Only parse the routes file if it has changed, or the project has not
  # been bootstrapped.
  if (resource_object$any_dependencies_modified() ||
      !isTRUE(director$.cache$bootstrapped)) {
    lapply(names(output), function(route) {
      controller <- output[[route]]
      if (!is.character(controller) && !is.function(controller)) {
        error("Every route must be a character or a function (your route ",
              director:::colourise(sQuote(route), 'yellow'), " is of type ",
              sQuote(class(controller)[1]), ")")
      }

      if (is.character(controller)) {
        controller <- director$resource(file.path('lib', 'controllers', controller))
        controller <- controller$value()
      }

      director$register_parser(route, controller)
      # TODO: (RK) More validations on routes?
    })
  }

  director$.cache$bootstrapped <- TRUE
}
