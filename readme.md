# report-compiler
Generate reports from YAML files using [wkhtmltopdf](http://wkhtmltopdf.org/).

## Install
```bash
npm install -g report-compiler
```

## Usage
```bash
report invoice.yml
# Outputs invoice.pdf
```

See `samples` directory for [an annotated sample](https://github.com/NicoJuicy/report-compiler/tree/master/samples42.yml).


## Dependencies
* node & npm
* [wkhtmltopdf](https://github.com/devongovett/node-wkhtmltopdf#installation)
* [Open Sans](http://www.fontsquirrel.com/fonts/open-sans) font


## Credits
The default template is based on a LaTeX class by Patrick Lühne, [http://www.luehne.de/](http://www.luehne.de/).

## License
MIT &copy; scalable minds 2014