import ghidra.app.decompiler.*;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;

public class DecompFunc extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        Address a = toAddr(args[0]);
        Function f = getFunctionAt(a);
        if (f == null) { println("NO FUNC at " + a); return; }
        DecompInterface di = new DecompInterface();
        di.openProgram(currentProgram);
        DecompileResults r = di.decompileFunction(f, 120, monitor);
        if (!r.decompileCompleted()) { println("FAIL " + r.getErrorMessage()); return; }
        println(r.getDecompiledFunction().getC());
        di.dispose();
    }
}
