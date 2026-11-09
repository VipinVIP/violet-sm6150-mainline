import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.DataIterator;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;

public class ImxHunter extends GhidraScript {
    @Override
    public void run() throws Exception {
        int n = 0;
        DataIterator it = currentProgram.getListing().getDefinedData(true);
        while (it.hasNext()) {
            Data d = it.next();
            Object v = d.getValue();
            if (v instanceof String) {
                String s = (String) v;
                if (s.toLowerCase().contains("imx586")) {
                    println("STR " + d.getAddress() + " :: " + s);
                    for (Reference r : getReferencesTo(d.getAddress())) {
                        Function f = getFunctionContaining(r.getFromAddress());
                        println("    ref@ " + r.getFromAddress() + " func=" + (f == null ? "?" : f.getName() + "@" + f.getEntryPoint()));
                    }
                    n++;
                }
            }
        }
        println("TOTAL imx586 strings: " + n);
    }
}
